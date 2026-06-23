// Custom Auth Handler to support custom scopes
//01-27-2026 Updated code to get roles from MapIdTokenClaims
global class GMAzureAuthPlugin extends Auth.AuthProviderPluginClass {
    private String clientId;
    private String clientSecret;
    private String accessTokenUrl;
    private String authorizationUrl;
    private String scope;
    private String userInfoUrl;
    private String redirectUri;
    
    private String sfdcstate;
    private String log;
    private String strAccessToken;
    private String strRefreshToken;
    private String strIdToken;
    private String authcode;
    private SSOLogEnqueue ssolog;
    private String SSOProviderName;
    public Onstar_Auth__c currentUserAuthInfo;
    public Boolean updateSSOInfo = false;
    public Boolean testRunFlag = false;
    private static final String curntuserid = UserInfo.getUserId();
    
    public GMAzureAuthPlugin(){
        super();
        system.debug('constructor called check 1');
        UserProvisioningUtil UserUtil = new UserProvisioningUtil();
        SSOProviderName = UserUtil.getSSOProviderName();
        
    }
    // This method is responsible for returning the custom metadata storing the api credentials and other details
    global String getCustomMetadataType() {
        return 'AzureAuthConfiguration__mdt';
    }
    
    // This method is responsible to initiate the authorization code flow
    global PageReference initiate(Map<String, String> authProviderConfiguration, String stateToPropagate) {
        Long startTime = System.currentTimeMillis();
        try{
            clientId = authProviderConfiguration.get('ClientId__c');
            authorizationUrl = authProviderConfiguration.get('AuthUrl__c');
            scope = authProviderConfiguration.get('Scope__c');
            system.debug('scope in initiate ==' + scope);
            redirectUri = authProviderConfiguration.get('CallbackUrl__c');
            String url = authorizationUrl + '?response_type=code'+'&scope='+ scope + '&client_id='+clientId+'&redirect_uri='+redirectUri+'&state='+stateToPropagate;
            system.debug('initiate url == ' + url);
            ssolog = new SSOLogEnqueue(url);
            PageReference pageref = new PageReference(url);
            return pageref;
            
        }catch(Exception ex){
            system.debug('handling exception in initiate ==' + ex.getMessage());
            String errorMsg = String.format('Exception occurred in {0}: {1}', new List<String>{'GMAzureAuthPlugin-initiate', ex.getMessage()});
            return null;
        }finally{
            Long endTime = System.currentTimeMillis();
        }
    }
    
    global Auth.AuthProviderTokenResponse handleCallback(Map<String, String> authProviderConfiguration, Auth.AuthProviderCallbackState state) {
        Long startTime = System.currentTimeMillis();
        log ='';
        system.debug('inside AuthProviderTokenResponse');
        try{
        clientId = authProviderConfiguration.get('ClientId__c');
        clientSecret = authProviderConfiguration.get('ClientSecret__c');
        scope = authProviderConfiguration.get('Scope__c');
        redirectUri = authProviderConfiguration.get('CallbackUrl__c');
        accessTokenUrl = authProviderConfiguration.get('AccessTokenUrl__c');
        authorizationUrl = authProviderConfiguration.get('AuthUrl__c');
        Map<String,String> queryParams = state.queryParameters;
        system.debug('query params size ==' + queryParams.size());
        String code = queryParams.get('code');
        authcode = code;
        sfdcState = queryParams.get('state');
        
        Map<String,String> params = new Map<String,String>();
        params.put('grant_type', 'authorization_code');
        params.put('client_id', clientId);
        params.put('client_secret', clientSecret);
        params.put('code', code);
        params.put('redirect_uri', redirectUri);
        params.put('scope', scope);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(accessTokenUrl);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setMethod('POST');
        String reqbody = encodeAsURL(params);
        req.setBody(reqbody);
        Http http = new Http();
        HTTPResponse res = http.send(req);
        String responseBody = res.getBody();
        log += responseBody + '----\n';
        system.debug('responseBody ==' + responseBody);
        system.debug('response status code ==' + res.getStatusCode());
        if (res.getStatusCode() == 200) {
            log +=  'inside statuscode 200----\n';
            Map<String, Object> responsemap = (Map<String, Object>) JSON.deserializeUntyped(responsebody); 
            log += 'response map size ==' + responsemap.size() + '----\n';
            strAccessToken = responsemap.get('access_token')?.toString();
            strRefreshToken = responsemap.get('refresh_token')?.toString();
            strIdToken = responsemap.get('id_token')?.toString() ;         
            return new Auth.AuthProviderTokenResponse(SSOProviderName, strAccessToken, clientSecret, sfdcstate);
            
        }else {
            log += 'responsebody for unsuccessful call==='+ responsebody + '----\n';
            SSOLogEnqueue ssolog = new SSOLogEnqueue(log);
            System.enqueueJob(ssolog);
            return new Auth.AuthProviderTokenResponse(SSOProviderName, null, clientSecret, sfdcstate);
        }
        }catch(Exception ex){
            String errorMsg = String.format('Exception occurred in {0}: {1}', new List<String>{'GMAzureAuthPlugin-handleCallback', ex.getMessage()});
            return null;
        }finally{
            Long endTime = System.currentTimeMillis();
        }
    }
    
    // This method is responsible to get the user information used for authentication from the external api	
    global Auth.UserData getUserInfo(Map<String, String> authProviderConfiguration, Auth.AuthProviderTokenResponse response) {
        
        String[] AccessTokenParts = strAccessToken.split('\\.');
        Blob AccessTokenDecoded = EncodingUtil.base64Decode(AccessTokenParts[1]); 
        Map<String, Object> MapAccessTokenClaims = (Map<String, Object>)JSON.deserializeUntyped(AccessTokenDecoded.toString());
        
        // Enqueue job to log all MapAccessTokenClaims keys and values
        // System.enqueueJob(new MapAccessTokenClaimsLogger(MapAccessTokenClaims));
        
        String[] IdTokenParts = strIdToken.split('\\.');
        Blob IdTokenDecoded = EncodingUtil.base64Decode(IdTokenParts[1]); 
        Map<String, Object> MapIdTokenClaims = (Map<String, Object>)JSON.deserializeUntyped(IdTokenDecoded.toString());
        
        // Enqueue job to log all MapIdTokenClaims keys and values
        // System.enqueueJob(new MapIdTokenClaimsLogger(MapIdTokenClaims));
        
        System.debug('MapIdTokenClaims: ' + MapIdTokenClaims);
        String identifier = (null != MapIdTokenClaims.get('uid')) ? (String)MapIdTokenClaims.get('uid'): '' ; 
        String firstName = (null != MapAccessTokenClaims.get('given_name'))? (String)MapAccessTokenClaims.get('given_name'):'' ; 
        String lastName = (null != MapAccessTokenClaims.get('family_name'))? (String)MapAccessTokenClaims.get('family_name'): '' ; 
        String fullName = (null != MapAccessTokenClaims.get('name'))? (String)MapAccessTokenClaims.get('name'): '' ;  
        String email = (null != MapIdTokenClaims.get('email')) ? (String)MapIdTokenClaims.get('email') : '';
        String link = null;
        String userName = (null != MapIdTokenClaims.get('email')) ? (String)MapIdTokenClaims.get('email') + '.ocrm' : ''; 
        String locale = 'en-US';
        String provider = SSOProviderName ; 
        String siteLoginUrl = null; 
        String roles = (null != MapIdTokenClaims.get('roles')) ? String.valueOf(MapIdTokenClaims.get('roles')) : '';
        String displayName = (null != MapAccessTokenClaims.get('displayName')) ? String.valueOf(MapAccessTokenClaims.get('displayName')) : '';
        String gmin = (null != MapAccessTokenClaims.get('gmuniqueidentifier')) ? String.valueOf(MapAccessTokenClaims.get('gmuniqueidentifier')) : '';

        Map<String,String> mapAdditionalAttributes = new Map<String,String>();
        mapAdditionalAttributes.put('access_token', strAccessToken);
        mapAdditionalAttributes.put('id_token',strIdToken);
        mapAdditionalAttributes.put('refresh_token',strRefreshToken);
        mapAdditionalAttributes.put('user_roles', roles);
        mapAdditionalAttributes.put('auth_code', authcode);
        mapAdditionalAttributes.put('gm_id', identifier);
        mapAdditionalAttributes.put('displayName', displayName);
        mapAdditionalAttributes.put('gmin', gmin);
        return new Auth.UserData(
            identifier,
            firstName,
            lastName,
            fullName,
            email,
            link, 
            userName,
            locale,
            provider,
            siteLoginUrl,
            mapAdditionalAttributes
        );
        
    }
    
    
    public String GetRefreshedAccessToken(String UserId){
        currentUserAuthInfo = [select Auth_Code__c, Refresh_token__c, Access_Token__c, Id_Token__c, UserID__c, GM_Id__c from Onstar_Auth__c where UserID__c =: UserId order by lastmodifieddate limit 1];
        String code = currentUserAuthInfo?.Auth_Code__c;
        String refresh_token = currentUserAuthInfo?.Refresh_token__c;
        String accesstoken = currentUserAuthInfo?.Access_Token__c;
        if(testRunFlag || isTokenValid(accesstoken)){
            return accesstoken;
        }else{
            getAttribuesForTokenEndPoint();
            Map<String,String> params = new Map<String,String>();
            params.put('grant_type', 'refresh_token');
            params.put('client_id', clientId);
            params.put('client_secret', clientSecret);
            params.put('refresh_token', refresh_token);
            params.put('redirect_uri', redirectUri);
            String NewAccessToken = invokeTokenEndpoint(params, currentUserAuthInfo);
            updateSSOInfo = true;
            return NewAccessToken;
        }
    }
    
    private String invokeTokenEndpoint(Map<String,String> params, Onstar_Auth__c currentUserAuthInfo){
        HttpRequest req = new HttpRequest();
        req.setEndpoint(accessTokenUrl);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setMethod('POST');
        String reqbody = encodeAsURL(params);
        req.setBody(reqbody);
        Http http = new Http();
        HTTPResponse res = http.send(req);
        String responseBody = res.getBody();
        log += responseBody + '----\n';
        system.debug('response status code ==' + res.getStatusCode());
        
        if (res.getStatusCode() == 200) {
            log +=  'inside statuscode 200----\n';
            Map<String, Object> responsemap = (Map<String, Object>) JSON.deserializeUntyped(responsebody); 
            log += 'response map size ==' + responsemap?.size() + '----\n';
            strAccessToken = responsemap.get('access_token')?.toString();
            strRefreshToken = responsemap.get('refresh_token')?.toString();
            strIdToken = responsemap.get('id_token')?.toString();
            currentUserAuthInfo.Access_Token__c = strAccessToken;
            currentUserAuthInfo.Refresh_Token__c = strRefreshToken;
            currentUserAuthInfo.Id_Token__c = strIdToken;
            String currentuserid = currentUserAuthInfo.UserID__c;
            return strAccessToken;
        }else return null;
    }
    
    
    Private void getAttribuesForTokenEndPoint(){
        AzureAuthConfiguration__mdt AzureAuthConfig = AzureAuthConfiguration__mdt.getInstance(SSOProviderName);
        clientId = AzureAuthConfig.ClientId__c;
        clientSecret = AzureAuthConfig.ClientSecret__c;
        scope = AzureAuthConfig.Scope__c;
        accessTokenUrl = AzureAuthConfig.AccessTokenUrl__c;
        redirectUri = AzureAuthConfig.CallbackUrl__c;
    }
    
    public boolean isTokenValid(String accesstoken){
        String[] AccessTokenParts = accesstoken.split('\\.');
        Blob AccessTokenDecoded = EncodingUtil.base64Decode(AccessTokenParts[1]); 
        Map<String, Object> MapAccessTokenClaims = (Map<String, Object>)JSON.deserializeUntyped(AccessTokenDecoded.toString());
        String strepochtime = String.valueOf(MapAccessTokenClaims.get('exp')) ;
        Long epochlong = Long.valueOf(strepochtime);
        DateTime epochtime = DateTime.newInstance(epochlong * 1000);
        DateTime currenttime = DateTime.now();
        if (currenttime > epochtime) {
            return false;
        } else return true;
    }
    
    
    private String encodeAsURL(Map<String,String> params) {
        String output = '';
        for (String key : params.keySet()) {
            output += (String.isEmpty(output) ? '' : '&');
            output += key + '=' + params.get(key);
        }
        return output;
    }
    
    // Inner class to log MapAccessTokenClaims keys and values
    // public class MapAccessTokenClaimsLogger implements Queueable {
    //     private Map<String, Object> mapAccessTokenClaims;
        
    //     public MapAccessTokenClaimsLogger(Map<String, Object> mapAccessTokenClaims) {
    //         this.mapAccessTokenClaims = mapAccessTokenClaims;
    //     }
        
    //     public void execute(QueueableContext context) {
    //         String logContent = '[MapAccessTokenClaimsLogger] Logging all keys and values:\n';
    //         logContent += 'Total number of claims: ' + mapAccessTokenClaims.size() + '\n\n';
            
    //         for (String key : mapAccessTokenClaims.keySet()) {
    //             Object value = mapAccessTokenClaims.get(key);
    //             String valueString = '';
                
    //             if (value == null) {
    //                 valueString = 'null';
    //             } else {
    //                 // Serialize all values (handles primitives, Lists, Maps, etc.)
    //                 valueString = JSON.serialize(value);
    //             }
                
    //             logContent += 'Key: ' + key + ' | Value: ' + valueString + '\n';
    //         }
            
    //         SSOLog__c logRecord = new SSOLog__c();
    //         logRecord.name = String.valueOf(System.now());
    //         logRecord.Log__c = logContent;
    //         insert logRecord;
    //     }
    // }
    
    // // Inner class to log MapIdTokenClaims keys and values
    // public class MapIdTokenClaimsLogger implements Queueable {
    //     private Map<String, Object> mapIdTokenClaims;
        
    //     public MapIdTokenClaimsLogger(Map<String, Object> mapIdTokenClaims) {
    //         this.mapIdTokenClaims = mapIdTokenClaims;
    //     }
        
    //     public void execute(QueueableContext context) {
    //         String logContent = '[MapIdTokenClaimsLogger] Logging all keys and values:\n';
    //         logContent += 'Total number of claims: ' + mapIdTokenClaims.size() + '\n\n';
            
    //         for (String key : mapIdTokenClaims.keySet()) {
    //             Object value = mapIdTokenClaims.get(key);
    //             String valueString = '';
                
    //             if (value == null) {
    //                 valueString = 'null';
    //             } else {
    //                 // Serialize all values (handles primitives, Lists, Maps, etc.)
    //                 valueString = JSON.serialize(value);
    //             }
                
    //             logContent += 'Key: ' + key + ' | Value: ' + valueString + '\n';
    //         }
            
    //         SSOLog__c logRecord = new SSOLog__c();
    //         logRecord.name = String.valueOf(System.now());
    //         logRecord.Log__c = logContent;
    //         insert logRecord;
    //     }
    // }
}