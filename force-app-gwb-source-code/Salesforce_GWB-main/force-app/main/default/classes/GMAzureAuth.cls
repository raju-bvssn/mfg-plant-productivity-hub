// Custom Auth Handler to support custom scopes
//10-10-23 Updated code to fix token persisting issues
global class GMAzureAuth extends Auth.AuthProviderPluginClass {
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
    private String SSOProviderName; //Added to dynamically generate SSO ProviderName

    public GMAzureAuth(){
     //   system.debug('in constructor before super');i
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
        try{
            clientId = authProviderConfiguration.get('ClientId__c');
            authorizationUrl = authProviderConfiguration.get('AuthUrl__c');
            scope = authProviderConfiguration.get('Scope__c');
            system.debug('scope in initiate ==' + scope);
            redirectUri = authProviderConfiguration.get('CallbackUrl__c');
            String url = authorizationUrl + '?response_type=code'+'&scope='+ scope + '&client_id='+clientId+'&redirect_uri='+redirectUri+'&state='+stateToPropagate;
            system.debug('initiate url == ' + url);
            ssolog = new SSOLogEnqueue(url);
            System.enqueueJob(ssolog);
            //   String encodedUrl = EncodingUtil.urlEncode(url, 'UTF-8');
            PageReference pageref = new PageReference(url);
            //   pageref.setRedirect(true);
            return pageref;

            }catch(Exception ex){
                system.debug('handling exception in initiate ==' + ex.getMessage());
            	String errorMsg = String.format('Exception occurred in {0}: {1}\nContext: {2}', new List<String>{'GMAzureAuth-initiate', ex.getMessage(), 'handling exception in initiate'});
                return null;
            }
    }
    
    global Auth.AuthProviderTokenResponse handleCallback(Map<String, String> authProviderConfiguration, Auth.AuthProviderCallbackState state) {
        // String log;
        log ='';
        system.debug('inside AuthProviderTokenResponse');
       clientId = authProviderConfiguration.get('ClientId__c');
        //    log += 'clientId =='+ clientId + '----\n';
       clientSecret = authProviderConfiguration.get('ClientSecret__c');
        //    log += clientSecret + '----\n';
       scope = authProviderConfiguration.get('Scope__c');
        //      log += scope + '----\n';
       redirectUri = authProviderConfiguration.get('CallbackUrl__c');
        //     log += redirectUri + '----\n';
       accessTokenUrl = authProviderConfiguration.get('AccessTokenUrl__c');
        //     log += accessTokenUrl + '----\n';
       authorizationUrl = authProviderConfiguration.get('AuthUrl__c');
        //     log += authorizationUrl + '----\n';
       Map<String,String> queryParams = state.queryParameters;
       system.debug('query params size ==' + queryParams.size());
       String code = queryParams.get('code');
        authcode = code;
        //     log += code + '----\n';
       sfdcState = queryParams.get('state');
        //     log += sfdcState + '----\n';
       
       Map<String,String> params = new Map<String,String>();
       params.put('grant_type', 'authorization_code');
       params.put('client_id', clientId);
       params.put('client_secret', clientSecret);
       params.put('code', code);
       params.put('redirect_uri', redirectUri);
       params.put('scope', scope);
                                   
       HttpRequest req = new HttpRequest();
       req.setEndpoint(accessTokenUrl);
        //     req.setHeader('Accept','application/json, application/x-www-form-urlencoded');
       req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
       req.setMethod('POST');
       String reqbody = encodeAsURL(params);
       req.setBody(reqbody);
        //   accessTokenUrl += '?response_type=token&client_id='+clientId+'&client_secret='+clientSecret+'&code='+code+'&redirect_uri='+redirectUri+'&state='+sfdcState;
        //     log += reqbody + '----\n';
        Http http = new Http();
       HTTPResponse res = http.send(req);
       String responseBody = res.getBody();
       log += responseBody + '----\n';
       system.debug('responseBody ==' + responseBody);
       system.debug('response status code ==' + res.getStatusCode());
       if (res.getStatusCode() == 200) {
       log +=  'inside statuscode 200----\n';
        //    log += responseBody + '----\n';
       Map<String, Object> responsemap = (Map<String, Object>) JSON.deserializeUntyped(responsebody); 
       log += 'response map size ==' + responsemap.size() + '----\n';
        // String blobacctok = EncodingUtil.base64Encode(responsemap.get('access_token'));
        strAccessToken = responsemap.get('access_token').toString();
        strRefreshToken = responsemap.get('refresh_token').toString();
        strIdToken = responsemap.get('id_token').toString();

        //return new Auth.AuthProviderTokenResponse('GMAzure_PreProd', strAccessToken, clientSecret, sfdcstate);
        return new Auth.AuthProviderTokenResponse(SSOProviderName, strAccessToken, clientSecret, sfdcstate);
        }else {
            log += 'responsebody for unsuccessful call==='+ responsebody + '----\n';
            SSOLogEnqueue ssolog = new SSOLogEnqueue(log);
            System.enqueueJob(ssolog);
            //return new Auth.AuthProviderTokenResponse('GMAzure_PreProd', null, clientSecret, sfdcstate);
            return new Auth.AuthProviderTokenResponse(SSOProviderName, null, clientSecret, sfdcstate);
        }
    }
    // This method is responsible to get the user information used for authentication from the external api
    global Auth.UserData getUserInfo(Map<String, String> authProviderConfiguration, Auth.AuthProviderTokenResponse response) {
    
        String[] AccessTokenParts = strAccessToken.split('\\.');
        Blob AccessTokenDecoded = EncodingUtil.base64Decode(AccessTokenParts[1]); 
        Map<String, Object> MapAccessTokenClaims = (Map<String, Object>)JSON.deserializeUntyped(AccessTokenDecoded.toString());
        
        String[] IdTokenParts = strIdToken.split('\\.');
        Blob IdTokenDecoded = EncodingUtil.base64Decode(IdTokenParts[1]); 
        Map<String, Object> MapIdTokenClaims = (Map<String, Object>)JSON.deserializeUntyped(IdTokenDecoded.toString());
        
        String identifier = (String)MapIdTokenClaims.get('uid') ; 
        String firstName = (String)MapAccessTokenClaims.get('given_name') ; 
        String lastName = (String)MapAccessTokenClaims.get('family_name') ; 
        String fullName = (String)MapAccessTokenClaims.get('name') ;  
        String email = (String)MapIdTokenClaims.get('email');
        String link = null;
        String userName = (String)MapIdTokenClaims.get('email') + '.ocrm'; 
        String locale = 'en-US';
        String provider = SSOProviderName ; 
        String siteLoginUrl = null; 
        String roles = String.valueOf(MapAccessTokenClaims.get('roles'));
        
        Map<String,String> mapAdditionalAttributes = new Map<String,String>();
        mapAdditionalAttributes.put('access_token', strAccessToken);
        mapAdditionalAttributes.put('id_token',strIdToken);
        mapAdditionalAttributes.put('refresh_token',strRefreshToken);
        mapAdditionalAttributes.put('user_roles', roles);
        mapAdditionalAttributes.put('auth_code', authcode);
        mapAdditionalAttributes.put('gm_id', identifier);
        
     
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
        Onstar_Auth__c currentUserAuthInfo = [select Auth_Code__c, Refresh_token__c, Access_Token__c, Id_Token__c, UserID__c from Onstar_Auth__c where UserID__c =: UserId order by lastmodifieddate limit 1];
        String code = currentUserAuthInfo.Auth_Code__c;
        String refresh_token = currentUserAuthInfo.Refresh_token__c;
        getAttribuesForTokenEndPoint();
        Map<String,String> params = new Map<String,String>();
        params.put('grant_type', 'refresh_token');
        params.put('client_id', clientId);
        params.put('client_secret', clientSecret);
        params.put('refresh_token', refresh_token);
        params.put('redirect_uri', redirectUri);
        //  params.put('scope', scope);
        String NewAccessToken = invokeTokenEndpoint(params, currentUserAuthInfo);
        system.debug('NewAccessToken ==' + NewAccessToken);
        return NewAccessToken;
        
    }
    
    private String invokeTokenEndpoint(Map<String,String> params, Onstar_Auth__c currentUserAuthInfo){
        HttpRequest req = new HttpRequest();
        req.setEndpoint(accessTokenUrl);
            //     req.setHeader('Accept','application/json, application/x-www-form-urlencoded');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setMethod('POST');
        String reqbody = encodeAsURL(params);
        req.setBody(reqbody);
        //   accessTokenUrl += '?response_type=token&client_id='+clientId+'&client_secret='+clientSecret+'&code='+code+'&redirect_uri='+redirectUri+'&state='+sfdcState;
        //     log += reqbody + '----\n';
        Http http = new Http();
        HTTPResponse res = http.send(req);
        String responseBody = res.getBody();
        log += responseBody + '----\n';
        system.debug('responseBody ==' + responseBody);
        system.debug('response status code ==' + res.getStatusCode());
        if (res.getStatusCode() == 200) {
        log +=  'inside statuscode 200----\n';
            //    log += responseBody + '----\n';
        Map<String, Object> responsemap = (Map<String, Object>) JSON.deserializeUntyped(responsebody); 
        log += 'response map size ==' + responsemap.size() + '----\n';
        // String blobacctok = EncodingUtil.base64Encode(responsemap.get('access_token'));
        strAccessToken = responsemap.get('access_token').toString();
        strRefreshToken = responsemap.get('refresh_token').toString();
        strIdToken = responsemap.get('id_token').toString();
        currentUserAuthInfo.Access_Token__c = strAccessToken;
        currentUserAuthInfo.Refresh_Token__c = strRefreshToken;
        currentUserAuthInfo.Id_Token__c = strIdToken;
        SSOLogEnqueue ssolog = new SSOLogEnqueue(currentUserAuthInfo);
        System.enqueueJob(ssolog);
        return strAccessToken;
        }else return null;
    }
    
    
    Private void getAttribuesForTokenEndPoint(){
        //AzureAuthConfiguration__mdt AzureAuthConfig = AzureAuthConfiguration__mdt.getInstance('GMAzure_PreProd');
        AzureAuthConfiguration__mdt AzureAuthConfig = AzureAuthConfiguration__mdt.getInstance(SSOProviderName);
        clientId = AzureAuthConfig.ClientId__c;
        //    log += 'clientId =='+ clientId + '----\n';
        clientSecret = AzureAuthConfig.ClientSecret__c;
        //    log += clientSecret + '----\n';
        scope = AzureAuthConfig.Scope__c;
        //      log += scope + '----\n';
        accessTokenUrl = AzureAuthConfig.AccessTokenUrl__c;
       
        redirectUri = AzureAuthConfig.CallbackUrl__c;

    }

   private String encodeAsURL(Map<String,String> params) {
        String output = '';
        for (String key : params.keySet()) {
            output += (String.isEmpty(output) ? '' : '&');
            output += key + '=' + params.get(key);
        }
        return output;
    }
}