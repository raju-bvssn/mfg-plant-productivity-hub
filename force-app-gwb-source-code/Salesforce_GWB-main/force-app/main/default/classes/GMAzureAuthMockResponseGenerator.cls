@istest
global class GMAzureAuthMockResponseGenerator implements HttpCalloutMock{
    global HTTPResponse respond(HTTPRequest req){
        
        Map<String,String> tokenMap = new Map<String,String>();
        tokenMap.put('uid', '005DN000000ABCD');
        tokenMap.put('given_name', 'Kapil');
        tokenMap.put('family_name', 'Kapil');
        tokenMap.put('name', 'Kapil');
        tokenMap.put('email', 'test@testcom');
        tokenMap.put('roles', 'Advisor');
        
        //String tokenMapValue = tokenMap.toString();
        String tokenMapValue = JSON.serialize(tokenMap);
        Blob myBlob = Blob.valueof(tokenMapValue);
        String tokenValue = '1234.'+EncodingUtil.base64Encode(myBlob);
        
        HttPResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody('{ "access_token" : "'+tokenValue+'", "refresh_token" : "'+tokenValue+'", "id_token" : "'+tokenValue+'" }');
        res.setStatus('Success');
        res.setStatusCode(200);
        return res;
    }
}