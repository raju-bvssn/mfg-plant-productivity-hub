@isTest global with sharing class GMAzureAuthTest{
    
    private static final String OAUTH_TOKEN = '1234.eyJyb2xlcyI6IkFkdmlzb3IiLCJlbWFpbCI6InRlc3RAdGVzdGNvbSIsIm5hbWUiOiJLYXBpbCIsImZhbWlseV9uYW1lIjoiS2FwaWwiLCJnaXZlbl9uYW1lIjoiS2FwaWwiLCJ1aWQiOiIwMDVETjAwMDAwMEFCQ0QifQ==';
    private static final String SECRET = 'testSecret';
    private static final String STATE_TO_PROPOGATE  = 'testState';
    private static final String ACCESS_TOKEN_URL = 'http://www.dummyhost.com/accessTokenUri';
    private static final String AUTH_URL = 'http://www.dummy.com/authurl';
    private static String SSOProviderName = '';
    
    private static Map<String,String> setupAuthProviderConfig () {
        Map<String,String> authProviderConfiguration = new Map<String,String>();
        authProviderConfiguration.put('DeveloperName',SSOProviderName);
        authProviderConfiguration.put('ClientId__c','Test1234567890Id');
        authProviderConfiguration.put('AuthUrl__c', AUTH_URL);
        authProviderConfiguration.put('ClientSecret__c', SECRET);
        authProviderConfiguration.put('AccessTokenUrl__c', ACCESS_TOKEN_URL);
        authProviderConfiguration.put('Scope__c','openid profile email api://sec-authz-gmuser.pp.gm.com/.default');
        authProviderConfiguration.put('CallbackUrl__c','https://gm-onecrm--teamsint.sandbox.my.salesforce.com/services/authcallback/GMAzure_PreProd');
        return authProviderConfiguration;
    }
    
    static testMethod void testInitiateMethod() {
        String stateToPropogate = 'mocktestState';
        UserProvisioningUtil userutil = new UserProvisioningUtil();
        SSOProviderName = userutil.getSSOProviderName();
        Map<String,String> authProviderConfiguration = setupAuthProviderConfig();
        GMAzureAuth azureGMAuth = new GMAzureAuth();
        GMAzureAuthPlugin azureGMAuthPlugin = new GMAzureAuthPlugin();
        
        system.debug('ssoprovider name ==' + SSOProviderName);
        PageReference expectedUrl =  new PageReference(authProviderConfiguration.get('AuthUrl__c') + '?client_id='+ 
                                                       authProviderConfiguration.get('ClientId__c') +'&redirect_uri='+authProviderConfiguration.get('CallbackUrl__c') 
                                                       +'&response_type=code&scope='+ authProviderConfiguration.get('Scope__c') + '&state=' + STATE_TO_PROPOGATE);
        PageReference actualUrl = azureGMAuth.initiate(authProviderConfiguration, STATE_TO_PROPOGATE);
        PageReference actualUrlPlugin = azureGMAuthPlugin.initiate(authProviderConfiguration, STATE_TO_PROPOGATE);
        System.assertEquals(expectedUrl.getUrl(), actualUrl.getUrl());
    }
    
    static testMethod void testGMAzureAuthMethods() {
        Map<String,String> authProviderConfiguration = setupAuthProviderConfig();
        GMAzureAuth azureGMAuth = new GMAzureAuth();
        UserProvisioningUtil userutil = new UserProvisioningUtil();
        SSOProviderName = userutil.getSSOProviderName();
        system.debug('ssoprovider name ==' + SSOProviderName);
        Test.setMock(HttpCalloutMock.class, new GMAzureAuthMockResponseGenerator());
        
        Map<String,String> queryParams = new Map<String,String>();
        queryParams.put('code','code');
        queryParams.put('state','Success');
        
        Auth.AuthProviderCallbackState cbState = new Auth.AuthProviderCallbackState(null,null,queryParams);
        Auth.AuthProviderTokenResponse actualAuthProvResponse = azureGMAuth.handleCallback(authProviderConfiguration, cbState);
        Auth.AuthProviderTokenResponse expectedAuthProvResponse = new Auth.AuthProviderTokenResponse(SSOProviderName, OAUTH_TOKEN, 'testSecret', 'Success');
        
        String customMeta = azureGMAuth.getCustomMetadataType();
        Auth.AuthProviderTokenResponse tokenResp = new Auth.AuthProviderTokenResponse(SSOProviderName, 'tokenMapValue', 'Test1234567890Secret', 'Success');
        azureGMAuth.getUserInfo(authProviderConfiguration, tokenResp);
        
        System.assertEquals(expectedAuthProvResponse.provider, actualAuthProvResponse.provider);
        System.assertEquals(expectedAuthProvResponse.oauthToken, actualAuthProvResponse.oauthToken);
        System.assertEquals(expectedAuthProvResponse.oauthSecretOrRefreshToken, actualAuthProvResponse.oauthSecretOrRefreshToken);
        System.assertEquals(expectedAuthProvResponse.state, actualAuthProvResponse.state);
    }
    
    // static testMethod void testRefreshedAccessTokenMethod(){
    //     Onstar_Auth__c onStarAuth = new Onstar_Auth__c();
    //     onStarAuth.UserID__c = 'testUserId';
    //     onStarAuth.Auth_Code__c = 'testAuthCode';
    //     onStarAuth.Refresh_Token__c = 'testRefreshToken';
    //     onStarAuth.GM_Id__c = 'testGMId';
    //     insert onStarAuth;
        
    //     Test.setMock(HttpCalloutMock.class, new GMAzureAuthMockResponseGenerator());
    //     GMAzureAuth azureGMAuth = new GMAzureAuth();
    //     test.starttest();
    //     String newAccessToken = azureGMAuth.GetRefreshedAccessToken('testUserId');
    //     test.stoptest();
    // }
    
    // static testMethod void testRefreshedAccessTokenMethodwithinterface(){
    //     Onstar_Auth__c onStarAuth = new Onstar_Auth__c();
    //     onStarAuth.UserID__c = 'testUserId';
    //     onStarAuth.Auth_Code__c = 'testAuthCode';
    //     onStarAuth.Refresh_Token__c = 'testRefreshToken';
    //     onStarAuth.GM_Id__c = 'testGMId';
    //     onStarAuth.Enhanced_Token__c = 'testGMId';
    //     insert onStarAuth;
        
    //     Test.setMock(HttpCalloutMock.class, new GMAzureAuthMockResponseGenerator());
    //     OnStarKnowledgeArticleClass controller = new OnStarKnowledgeArticleClass();
    //     Map<String,Object> inputMap = new Map<String,Object>();
    //     Map<String,Object> outMap = new Map<String,Object>();
    //     Map<String,Object> options = new Map<String,Object>();
    //     test.starttest();
    //     controller.invokeMethod('getAccessToken',inputMap,outMap,options);
    //     inputMap.put('authid',onStarAuth.id);
    //     inputMap.put('Enhancedtoken','Bearer testGMId');
    //     controller.invokeMethod('getEnhancedAccessToken',inputMap,outMap,options);
    //     controller.invokeMethod('getOrgName',inputMap,outMap,options);
    //     controller.invokeMethod('throwexception',inputMap,outMap,options);
    //     test.stoptest();
    // }
    
    // static testMethod void testRefreshedAccessTokenMethodwithinterfaceexception(){
    //     OnStarKnowledgeArticleClass controller = new OnStarKnowledgeArticleClass();
    //     Map<String,Object> inputMap = new Map<String,Object>();
    //     Map<String,Object> outMap = new Map<String,Object>();
    //     Map<String,Object> options = new Map<String,Object>();
    //     controller.invokeMethod('throwexception',inputMap,outMap,options);
    // }
    
    static testMethod void testGMAzureAuthPluginMethods() {
        Map<String,String> authProviderConfiguration = setupAuthProviderConfig();
        GMAzureAuthPlugin azureGMAuth = new GMAzureAuthPlugin();
        UserProvisioningUtil userutil = new UserProvisioningUtil();
        SSOProviderName = userutil.getSSOProviderName();
        Test.setMock(HttpCalloutMock.class, new GMAzureAuthMockResponseGenerator());
        
        Map<String,String> queryParams = new Map<String,String>();
        queryParams.put('code','code');
        queryParams.put('state','Success');
        
        Auth.AuthProviderCallbackState cbState = new Auth.AuthProviderCallbackState(null,null,queryParams);
        Auth.AuthProviderTokenResponse actualAuthProvResponse = azureGMAuth.handleCallback(authProviderConfiguration, cbState);
        Auth.AuthProviderTokenResponse expectedAuthProvResponse = new Auth.AuthProviderTokenResponse(SSOProviderName, OAUTH_TOKEN, 'testSecret', 'Success');
        
        String customMeta = azureGMAuth.getCustomMetadataType();
        Auth.AuthProviderTokenResponse tokenResp = new Auth.AuthProviderTokenResponse(SSOProviderName, 'tokenMapValue', 'Test1234567890Secret', 'Success');
        azureGMAuth.getUserInfo(authProviderConfiguration, tokenResp);
        
        System.assertEquals(expectedAuthProvResponse.provider, actualAuthProvResponse.provider);
        System.assertEquals(expectedAuthProvResponse.oauthToken, actualAuthProvResponse.oauthToken);
        System.assertEquals(expectedAuthProvResponse.oauthSecretOrRefreshToken, actualAuthProvResponse.oauthSecretOrRefreshToken);
        System.assertEquals(expectedAuthProvResponse.state, actualAuthProvResponse.state);
    }
    
    // static testMethod void testRefreshedAccessTokenPluginMethod(){
    //     Onstar_Auth__c auth = new Onstar_Auth__c();
    //     auth.Access_Token__c='eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ii1LSTNROW5OUjdiUm9meG1lWm9YcWJIWkdldyIsImtpZCI6Ii1LSTNROW5OUjdiUm9meG1lWm9YcWJIWkdldyJ9.eyJhdWQiOiJhcGk6Ly9zZWMtYXV0aHotZ211c2VyLnBwLmdtLmNvbSIsImlzcyI6Imh0dHBzOi8vc3RzLndpbmRvd3MubmV0LzZiYWE0ZWIxLTEwNmEtNDQwYi1iNGY2LTUwMTM0NDk3ZDM2ZC8iLCJpYXQiOjE2OTc0MTA3MDEsIm5iZiI6MTY5NzQxMDcwMSwiZXhwIjoxNjk3NDE0ODk0LCJhY3IiOiIxIiwiYWlvIjoiQVZRQXEvOFVBQUFBeXhLK2JFRmkza3AxL2pCbkpjcGd0eHVSL0RTNlRrczdnRUdWVHVlaFBJQ05wQS9lTVRWZ3ZReDlMVkZjb2VQQmJjR01YZThkOFFGaWxWdnZyMXFHWkdUckNtVDFpZG1NSjM1ZXZRc1VGU0U9IiwiYW1yIjpbInB3ZCIsIm1mYSJdLCJhcHBpZCI6IjNmOWM3YTY2LWM5YjEtNGRiZi05ODJjLThiM2E1MmEyOGQzYiIsImFwcGlkYWNyIjoiMSIsImZhbWlseV9uYW1lIjoiU2Fob28iLCJnaXZlbl9uYW1lIjoiUmFqZXNoIEt1bWFyIiwiaXBhZGRyIjoiMTY1LjIyNS42Mi4xMTMiLCJuYW1lIjoiUmFqZXNoIEt1bWFyIFNhaG9vIChDKSIsIm9pZCI6IjcyNzZjNjg5LTljOGItNGQ5Ny05ODhiLWYxNzRkNDY0NzZjMCIsIm9ucHJlbV9zaWQiOiJTLTEtNS0yMS0yODQxNjIwMjUyLTM5MjUzNjI2MjAtMzkwMjkxMDIwOS0xMDc4Njg0IiwicmgiOiIwLkFSSUFzVTZxYTJvUUMwUzA5bEFUUkpmVGJUa0JPTDdsc2FGTWdOdktlX1BScFhVU0FOYy4iLCJyb2xlcyI6WyJvY3JtX3Nlc19hZHZpc29yIl0sInNjcCI6InVzZXJfaW1wZXJzb25hdGlvbiIsInN1YiI6InhabFpZaDJsR1B3YV85eVhSS0EwZmRYaXdlQ0QtSXVDV1pjUVE4UGR1ZFkiLCJ0aWQiOiI2YmFhNGViMS0xMDZhLTQ0MGItYjRmNi01MDEzNDQ5N2QzNmQiLCJ1bmlxdWVfbmFtZSI6IkZaUEszREBOQU1RQS5DT1JQUUEuR0VVQy5DT1JQLkdNLkNPTSIsInVwbiI6IkZaUEszREBOQU1RQS5DT1JQUUEuR0VVQy5DT1JQLkdNLkNPTSIsInV0aSI6IkE3aHlSMDdoSDBlMERPVElZZ1p3QUEiLCJ2ZXIiOiIxLjAiLCJkaXNwbGF5TmFtZSI6IlJhamVzaCBLdW1hciBTYWhvbyAoQykiLCJnaXZlbk5hbWUiOiJSYWplc2ggS3VtYXIiLCJ1aWQiOiJGWlBLM0QiLCJzbiI6IlNhaG9vIiwibWFpbCI6InJhamVzaGt1bWFyLnNhaG9vQGdtLmNvbSJ9.bJCCSvo-ELPLaUNzkECicxHCOOTOL1q2sZMj4lqsalE8lp1sJRlVVRFk2FckW2M-NNi0fPX_Of0jxvsW_HjO4k2ZBIk6ldXCJQwbSzfohE3eKT1i9KxmNf9IWcbPBT2iIrowFJI5yAde2UUsG3cOKMLsvYykUVwA4RQHz7DGsW3EAznBoqYX3KaHG-2cpljT2nIQE1tGgs2p4TkeJfcqk1XJ-oCA2FBfU1GtRzY-_h7aIPGWWPp7xAgYowJUgmQXGdcXosvf2YP1QAGXuLwn2eNvd1we2Hv-Bm0H-5xX2by2W7cIwuSFsMdIEKNOIPINuCeilD01sXqmoB0J5wxGgg';
    //     auth.Auth_Code__c='0.ARIAsU6qa2oQC0S09lATRJfTbWZ6nD-xyb9NmCyLOlKijTsSANc.AgABAAIAAAAtyolDObpQQ5VtlI4uGjEPAgDs_wUA9P8UVmXZmj3hWIueQv4AHc6AYc_c9HWCWh0GoBQGiEfAa4VItRiFSrFoOQQf1pgCja0UqWoT3yDiJCti1HXd3Jd1z2uL4xAtyRJXHwq212gfuvMSJZUAIJz3NL5Bd45d7Wcanvsz8_huebczyROev18hhBp10Zo5YP_HE0txwc6CK1WDHnxaJpmoo6UpDDAkhRavCif0dayhk0YXOnqp-H-T05xD7W_RBqxLW8jz7jel7SylbiCkDsrx9jDlylC9iSDPbqpirkvoJHdULPHmCSL6U8UrCBaUz30UmlufjCZrwxMFEUCzKlxWN5QhKnKuiaVklsrDSRT3rIiQdKiJX6ttrHwgIGue95Z_nXbBcaHRX0i9WiTLLhqt57ELAVBNFJUNiBISoIeCbCL1BU3JgatbH7fLuyt7uuSCvWMKF0Ikq663P8YWTfNOQB2ovGGwtrkZ-Rtcqptc3Aj2zxrm9AHTEgRrfbpkim4QDUPFlXg4VdAX7tljpfj1LtXgfGwUOxNNmkaee4xDoVIZXRw4zPgu9ELp1c3pLRXFkLWy2nvFzRAMWOAjQQO_2FPiBFU7xi6AOtG2QEIE3oiULaatqZ3ZuE3CIXqOHeQEHlkrQv3hhuRtTU2QzfdABugXWrEUTIGldM-7hg6nLbVaSbjeKJtrGpVA5SFedNyDKgoVGX8c1_ueQJr6nIjdk46g9VA1ckMujxxnu53BhoYQkpku1GJBlPs3Lhn5kfKDQVWJtR1ed1BbdbIePJyCtqusKhM8v6t33G_jYcAuePCvBMJI8BmbSLwLbO6DE5OMBgPUH02-FnwJnU4swqV5XJppYHqg9QNYpv1VXEJPQ4o0t3rplVYuiHp7cUn3M9RRAQ5djy0XGMzK2hXWZ1JlwaaDzdxaIZiVZqS_Lu4QadovbEahk0pHNPeWUT8kr2fAPKtkjSJrF8QzEK4Cb5UOT8YdI1HDVOjAjaB6rkrZ';
    //     auth.Id_Token__c='eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6Ii1LSTNROW5OUjdiUm9meG1lWm9YcWJIWkdldyJ9.eyJhdWQiOiIzZjljN2E2Ni1jOWIxLTRkYmYtOTgyYy04YjNhNTJhMjhkM2IiLCJpc3MiOiJodHRwczovL2xvZ2luLm1pY3Jvc29mdG9ubGluZS5jb20vNmJhYTRlYjEtMTA2YS00NDBiLWI0ZjYtNTAxMzQ0OTdkMzZkL3YyLjAiLCJpYXQiOjE2OTc0MTA3MDEsIm5iZiI6MTY5NzQxMDcwMSwiZXhwIjoxNjk3NDE0NjAxLCJlbWFpbCI6InJhamVzaGt1bWFyLnNhaG9vQGdtLmNvbSIsIm5hbWUiOiJSYWplc2ggS3VtYXIgU2Fob28gKEMpIiwib2lkIjoiNzI3NmM2ODktOWM4Yi00ZDk3LTk4OGItZjE3NGQ0NjQ3NmMwIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiRlpQSzNEQE5BTVFBLkNPUlBRQS5HRVVDLkNPUlAuR00uQ09NIiwicmgiOiIwLkFSSUFzVTZxYTJvUUMwUzA5bEFUUkpmVGJXWjZuRC14eWI5Tm1DeUxPbEtpalRzU0FOYy4iLCJyb2xlcyI6WyJvY3JtX3Nlc19hZHZpc29yIl0sInN1YiI6Il9TMzg0MklCN2ZaY04zNVAybzF5LTNSbXlldW9fYVRMcFBNNVZDWTYzZlUiLCJ0aWQiOiI2YmFhNGViMS0xMDZhLTQ0MGItYjRmNi01MDEzNDQ5N2QzNmQiLCJ1dGkiOiJBN2h5UjA3aEgwZTBET1RJWWdad0FBIiwidmVyIjoiMi4wIiwiZGlzcGxheU5hbWUiOiJSYWplc2ggS3VtYXIgU2Fob28gKEMpIiwiZ2l2ZW5OYW1lIjoiUmFqZXNoIEt1bWFyIiwidWlkIjoiRlpQSzNEIiwic24iOiJTYWhvbyJ9.LydTSXZ7zhZ13x1XA1pnLA5LNjBIQ3hD6QNiyOTNTMcaQG1XphnRUC7TPz_P7Vw9PsRmPf3ZuCI2DQ4F0eNIchL-LxOzBA4C82es7paNzOXpfVge6U8HHvV-wCsfKJqYV40TrGFPMNxI7bsR8hTqFY2j_FtrNP40T8BMWSY-OEGTZtUds9Zy6BQhQ6kW5P8_DamSFmVHXllAsbni6ojbnhwoCViwVzEc0nD_qVdpnqeeqXych3VZHVxTfFnVq0aMqDdoiBQewzKiT1vMlucOfogxyMpR95vSlCejU1-kty4iG7q017hr54gMjZDM4_KhdrqAbaRTHx2MUJT6DkM6lw';
    //     auth.GM_Id__c='testGMId';
    //     auth.Refresh_Token__c='0.ARIAsU6qa2oQC0S09lATRJfTbWZ6nD-xyb9NmCyLOlKijTsSANc.AgABAAEAAAAtyolDObpQQ5VtlI4uGjEPAgDs_wUA9P97_zB3GaVDtFIM3eGVA0qdKvhuVZFTuRn4v3rav5K4UQrkv8ciJYbFDa8T8kigo9oJcwltVC4A1nBuGwLMysTRNoQqcXI1Rzxi9zXyQJMAHasY2z--TRdEEGE2dEJDDOGBBDcda0rs-N62fyvXIiDH4KcJ0UqYade4oFpx4mOj7osGs--yZfpYympHzffgv6iPKdHrDAzB1HjgVs4qew_ls-ia-XRwbXfkxLjgC04UpenhEGJfgl5I_By3YVz-kcu-lD8CB0G5BcyCOkeYvVFDc7l5boKPj4PjSbPH-fqZ2UxVlmd7RbRKYJ6s69GpjqKgNIprO0bTVEfOZb9R_3f9xb4q20nrLMph6RQX4hDhrax1AvobYVS1WR5IJuIC1l8PGQFW9mAYRU57gd9QercnU6CBppjbHKAkVpogbWfnfgLMjie1kCiIQJDFkx0826DypAoe38eeXs0Qri0EVQE2Dv9BeLCkDi365zcsRK2qAL64aT4Im6QJbM0BX5YYZCwWqO6k1WLHU0ACjhGUVH3oDb85CqFW_Hhf7jqkjUfL6SEY7uoxk0qYkw1X9eMQ55M5PiAJYHGlpYcFPjFfSDWJ94yucuTLlh_ZXfOIZmR6eE68EYlTzeOenJF4xXPogC1imDMBYmVBMdTXVD0NZzBeOc0ud1qpYo7bkJ49-klDUZIDLNuVkqkHXc-VwK2lLP0OhxXIaVL777EYY5wjQ_JWr0b5YTqbntYzgKT6pTHDt8ULRu-W2m_3zI7xU1WkghxRJtebzjyw6mwCS8OIIwbGliVvo2CZYS3MmpqZwLgCs8Lb1NcTX5cXDY45OEnLd7GGdGMMSE18t5CB9zl0mVzHly9vO5OMSUyXCAl7O5mbjRO8FCJWWJq_mThcS7xq98ZcAoU';
    //     auth.UserID__c = 'testUserId';
    //     insert auth;
    //     Test.setMock(HttpCalloutMock.class, new GMAzureAuthMockResponseGenerator());
    //     GMAzureAuthPlugin azureGMAuth = new GMAzureAuthPlugin();
    //     UserProvisioningUtil userutil = new UserProvisioningUtil();
    //     SSOProviderName = userutil.getSSOProviderName();
    //     test.starttest();
    //     String newAccessToken = azureGMAuth.GetRefreshedAccessToken('testUserId');
    //     test.stoptest();
    // }
    
    // static testMethod void callMethodOnStarKnowledgeArticleClass(){
    //     String action;
    //     OnStarKnowledgeArticleClass controller = new OnStarKnowledgeArticleClass();
    //     Map<String,Object> args = new Map<String,Object>();
    //     controller.call(action, args);
        
    // }
}