{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE QuasiQuotes #-}

module Server.OAuth2.Google
( handleRoot
, readUserIdentityFromCookies
) where

import Server.OAuth2.Utils (isAllowedReferer, redirectToCurrentRefererIfAllowed)
import GHC.Generics
import Server.Core
import Happstack.Server
import System.Environment (getEnv)
import Data.Either.Combinators (rightToMaybe)
import Control.Monad (msum)
import Control.Monad.Extra (liftMaybe)
import Control.Monad.Trans (lift, liftIO)
import Control.Monad.Trans.Maybe (MaybeT(..), runMaybeT)
import URI.ByteString (URI, parseURI, strictURIParserOptions, serializeURIRef')
import URI.ByteString.QQ (uri)
import qualified Network.HTTP.Client as HC
import qualified Data.ByteString.Lazy.Char8 as BS8
import qualified Data.ByteString.Char8 as BSS8
import qualified Jose.Jwk as JWK
import qualified Jose.Jwt as JWT
import qualified Web.OIDC.Client as OIDC
import qualified Network.OAuth.OAuth2 as OA2
import qualified Data.Aeson as A
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString.Base64 as B64

data Claims = Claims
    { email :: T.Text
    , sub :: T.Text
    , email_verified :: Bool
    } deriving (Generic, Show)

instance A.FromJSON Claims where
    parseJSON = A.genericParseJSON A.defaultOptions

data UserInfo = UserInfo
    { given_name :: T.Text
    , family_name :: T.Text
    , picture :: T.Text
    } deriving (Generic, Show)

instance A.FromJSON UserInfo where
    parseJSON = A.genericParseJSON A.defaultOptions

refererCookieName :: String
refererCookieName = "google_referer"

identityTokenCookieName :: String
identityTokenCookieName = "google_identityToken"

userInfoCookieName :: String
userInfoCookieName = "google_userInfo"

-- The cookie for user info needs to be encoded as it contains the character ";", which causes issues in some browsers
encodeUserInfoText :: T.Text -> T.Text
encodeUserInfoText = TE.decodeUtf8 . B64.encode . TE.encodeUtf8

decodeUserInfoText :: T.Text -> Maybe T.Text
decodeUserInfoText = rightToMaybe . fmap TE.decodeUtf8 . B64.decode . TE.encodeUtf8

readUserIdentityFromCookies :: ServerResources -> ServerPart (Maybe UserIdentity)
readUserIdentityFromCookies serverResources = runMaybeT $ do
    -- Fetch cookie values
    identityTokenText <- lift $ T.pack <$> lookCookieValue identityTokenCookieName
    userInfoText <- MaybeT $ decodeUserInfoText . T.pack <$> lookCookieValue userInfoCookieName
    -- Extract claims
    claims <- MaybeT . liftIO . runMaybeT $ extractClaims serverResources identityTokenText
    -- Decode user info
    userInfo :: UserInfo <- liftMaybe $ A.decodeStrict (TE.encodeUtf8 userInfoText)
    -- Build response
    let userIdentifier = UserIdentifier "google" (sub claims)
    let userPictureUrl = picture userInfo
    let userGivenName = given_name userInfo
    let userFamilyName = family_name userInfo
    return $ UserIdentity userIdentifier userPictureUrl userGivenName userFamilyName

extractClaims :: ServerResources -> T.Text -> MaybeT IO Claims
extractClaims serverResources identityTokenText = do
    -- Decode jwt token
    googlePublicKeys <- liftIO $ getGooglePublicKeys serverResources
    jwtTokenEither <- liftIO $ JWT.decode googlePublicKeys Nothing (TE.encodeUtf8 identityTokenText)
    jwtToken <- liftMaybe $ rightToMaybe jwtTokenEither
    jwsPayload <- liftMaybe $ do
        case jwtToken of
            JWT.Jws (jwsHeader, jwsPayload) -> Just jwsPayload
            _ -> Nothing
    -- Extract claims
    claims <- liftMaybe $ A.decodeStrict jwsPayload
    -- Validate claims
    if (email_verified claims)
        then return claims
        else liftMaybe Nothing

handleRoot :: ServerResources -> ServerPart Response
handleRoot serverResources = msum
    [ dir "login" $ handleLogin
    , dir "logout" $ handleLogout
    , dir "callback" $ handleCallback serverResources
    ]

saveReferer :: ServerPart ()
saveReferer = do
    rq <- askRq
    let refererMaybe = do
            originalReferer <- BSS8.unpack <$> getHeader "Referer" rq
            if isAllowedReferer originalReferer then
                return originalReferer
            else
                Nothing
    case refererMaybe of
        Just referer -> addCookie Session $ mkCookie refererCookieName referer
        Nothing -> expireCookie refererCookieName
    return ()

redirectToSavedReferer :: ServerPart Response
redirectToSavedReferer = do
    referer <- lookCookieValue refererCookieName
    if isAllowedReferer referer then
        -- Redirect to referer
        tempRedirect referer $ toResponse ("" :: T.Text)
    else
        -- Redirect the homepage
        tempRedirect ("/" :: T.Text) $ toResponse ("" :: T.Text)

handleLogin :: ServerPart Response
handleLogin = do
    saveReferer
    authorizationUrl <- getAuthorizationUrl
    tempRedirect authorizationUrl $ toResponse ("" :: T.Text)

handleLogout :: ServerPart Response
handleLogout = do
    expireCookie identityTokenCookieName
    expireCookie userInfoCookieName
    redirectToCurrentRefererIfAllowed

handleCallback :: ServerResources -> ServerPart Response
handleCallback serverResources = do
    -- Retrieve exchange token from querystring
    -- TODO: also handle the 'state' parameter
    code <- lookText' "code"
    let exchangeToken = OA2.ExchangeToken code
    -- Acquire oauth2 token from Google
    let tlsManager = serverResourcesTlsManager serverResources
    oauth2Config <- getOAuth2Config
    oauth2TokenEither <- liftIO $ OA2.fetchAccessToken tlsManager oauth2Config exchangeToken
    case oauth2TokenEither of
        Left _ -> unauthorized $ toResponse ("Acquisition of oauth2 token failed." :: T.Text)
        Right oauth2Token -> do
            -- Extract access token
            let accessToken = OA2.accessToken oauth2Token
            -- Extract identity token
            case  OA2.idtoken <$> (OA2.idToken oauth2Token) of
                Nothing -> unauthorized $ toResponse ("Acquisition of identity token failed." :: T.Text)
                Just identityTokenText -> do
                    -- Extract claims
                    claimsMaybe <- liftIO $ runMaybeT $ extractClaims serverResources identityTokenText
                    case claimsMaybe of
                        Nothing -> unauthorized $ toResponse ("Decoding of identity token failed." :: T.Text)
                        Just claims -> do
                            -- Fetch user info
                            userInfoText <- liftIO $ fetchUserInfo serverResources accessToken
                            -- Validate user info
                            let userInfoMaybe = A.decodeStrict (TE.encodeUtf8 userInfoText) :: Maybe UserInfo
                            case userInfoMaybe of
                                Nothing -> unauthorized $ toResponse ("Decoding of user info failed." :: T.Text)
                                Just userInfo -> do
                                    -- Save identity token and user info to cookies
                                    let cookieDuration = (MaxAge $ 30 * 86400)
                                    addCookies $ (cookieDuration,) <$>
                                        [ mkCookie identityTokenCookieName $ T.unpack identityTokenText
                                        , mkCookie userInfoCookieName $ T.unpack . encodeUserInfoText $ userInfoText
                                        ]
                                    -- Redirect user back to referer
                                    redirectToSavedReferer

fetchUserInfo :: ServerResources -> OA2.AccessToken -> IO T.Text
fetchUserInfo serverResources accessToken = do
    let tlsManager = serverResourcesTlsManager serverResources
    let accessTokenString = T.unpack $ OA2.atoken accessToken
    request <- HC.parseRequest $ "https://www.googleapis.com/oauth2/v3/userinfo?access_token=" ++ accessTokenString
    response <- HC.httpLbs request tlsManager
    return $ TE.decodeUtf8 . BS8.toStrict $ HC.responseBody response

getGooglePublicKeys :: ServerResources -> IO [JWK.Jwk]
getGooglePublicKeys serverResources = do
    let tlsManager = serverResourcesTlsManager serverResources
    provider <- OIDC.discover "https://accounts.google.com" tlsManager
    return $ OIDC.jwkSet provider

getOAuth2Config :: ServerPart OA2.OAuth2
getOAuth2Config = do
    clientId <- liftIO $ getEnv "LOJBAN_TOOL_OAUTH2_GOOGLE_CLIENT_ID"
    clientSecret <- liftIO $ getEnv "LOJBAN_TOOL_OAUTH2_GOOGLE_CLIENT_SECRET"
    let defaultCallbackUri = [uri|https://lojban.io/oauth2/google/callback|]
    callbackUri <- msum [ getCallbackUri, return defaultCallbackUri ]
    return $ OA2.OAuth2
        { OA2.oauthClientId = T.pack clientId
        , OA2.oauthClientSecret = T.pack clientSecret
        , OA2.oauthCallback = Just callbackUri
        , OA2.oauthOAuthorizeEndpoint = [uri|https://accounts.google.com/o/oauth2/auth|]
        , OA2.oauthAccessTokenEndpoint = [uri|https://www.googleapis.com/oauth2/v3/token|]
        }

getCallbackUri :: ServerPart URI
getCallbackUri = do
    rq <- askRq
    case getHeader "host" rq of
        Nothing -> mempty
        Just rawHost -> do
            let host = TE.decodeUtf8 rawHost
            let scheme = if (T.takeWhile (/= ':') host) `elem` ["localhost", "127.0.0.1"] then "http" else "https"
            case parseURI strictURIParserOptions $ TE.encodeUtf8 $ T.concat [scheme, "://", host, "/oauth2/google/callback"] of
                Left _ -> mempty
                Right parsedURI -> return parsedURI

getAuthorizationUrl :: ServerPart T.Text
getAuthorizationUrl = do
    oauth2Config <- getOAuth2Config
    let params = [ ("scope", "email profile") ]
    let url = OA2.appendQueryParams params $ OA2.authorizationUrl oauth2Config
    return $ TE.decodeUtf8 $ serializeURIRef' url
