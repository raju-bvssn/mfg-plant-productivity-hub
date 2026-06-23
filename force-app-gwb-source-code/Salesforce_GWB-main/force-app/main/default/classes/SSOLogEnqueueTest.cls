@isTest(SeeAllData=true)
public class SSOLogEnqueueTest {
    
    
	static testmethod void testQueueable(){
     	String log ='amnsjd';
     	String name = 'amnsjd';
     	Onstar_Auth__c authinfo;
       
         List<Id> idLst = new List<Id>();
        for(Onstar_Auth__c objOuath : [SELECT Id, UserId__c FROM Onstar_Auth__c LIMIT 10]){
            idLst.add(objOuath.UserId__c);
        }
            List<User> usrs = [Select Id, Name from User WHERE ID NOT IN :idLst LIMIT 10];
        
        String accesstokenstring = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ii1LSTNROW5OUjdiUm9meG1lWm9YcWJIWkdldyIsImtpZCI6Ii1LSTNROW5OUjdiUm9meG1lWm9YcWJIWkdldyJ9.eyJhdWQiOiJhcGk6Ly9zZWMtYXV0aHotZ211c2VyLnBwLmdtLmNvbSIsImlzcyI6Imh0dHBzOi8vc3RzLndpbmRvd3MubmV0LzZiYWE0ZWIxLTEwNmEtNDQwYi1iNGY2LTUwMTM0NDk3ZDM2ZC8iLCJpYXQiOjE2ODk4NzE4NjAsIm5iZiI6MTY4OTg3MTg2MCwiZXhwIjoxNjg5ODc2ODM0LCJhY3IiOiIxIiwiYWlvIjoiQVZRQXEvOFRBQUFBelpOTlhXRTYvQ2hwNVNVOC9hK3k4ci9HL1p3bjZFRXE4bTZzWGtpUW4rdHFjNVNnQ085N2hzREIxUlNMNTNYY3NlMUV0WXFWejVoSU84TVUzWjBpeldCc0EweU5TRm94V3pCdEJYRXgweHM9IiwiYW1yIjpbInB3ZCIsIm1mYSJdLCJhcHBpZCI6IjNmOWM3YTY2LWM5YjEtNGRiZi05ODJjLThiM2E1MmEyOGQzYiIsImFwcGlkYWNyIjoiMSIsImZhbWlseV9uYW1lIjoiQmhhcmR3YWoiLCJnaXZlbl9uYW1lIjoiS2FwaWwiLCJpcGFkZHIiOiIxMDQuMTYxLjI0Ni4zOCIsIm5hbWUiOiJLYXBpbCBCaGFyZHdhaiAoQykiLCJvaWQiOiI3ODYxNDUxMS1mZmYxLTRlNDgtYmQ1MS0xNDJlYTYxOTY0ZmIiLCJvbnByZW1fc2lkIjoiUy0xLTUtMjEtMzQyOTAwODIwNS0xNTQ1MzUxMDQ2LTI3MDMzOTY2MzAtMTAyMjcyIiwicmgiOiIwLkFSSUFzVTZxYTJvUUMwUzA5bEFUUkpmVGJUa0JPTDdsc2FGTWdOdktlX1BScFhVU0FMby4iLCJyb2xlcyI6WyJvY3JtX2Nvbm5lY3RlZGFkdmlzb3IiLCIyMTkzMTVfT0NSTV9QUkVfUFJPRCJdLCJzY3AiOiJ1c2VyX2ltcGVyc29uYXRpb24iLCJzdWIiOiJkZEVlSGtqcmNSWFl4SXZzZkRnU2hRREZ0QldKUldtXzZURGxIX053dHN3IiwidGlkIjoiNmJhYTRlYjEtMTA2YS00NDBiLWI0ZjYtNTAxMzQ0OTdkMzZkIiwidW5pcXVlX25hbWUiOiJUWkROUkZAQVBBUUEuQ09SUFFBLkdFVUMuQ09SUC5HTS5DT00iLCJ1cG4iOiJUWkROUkZAQVBBUUEuQ09SUFFBLkdFVUMuQ09SUC5HTS5DT00iLCJ1dGkiOiIxUEgwTmlpN3BFQ0NObDlERHdnX0FBIiwidmVyIjoiMS4wIiwiZGlzcGxheU5hbWUiOiJLYXBpbCBCaGFyZHdhaiAoQykiLCJnaXZlbk5hbWUiOiJLYXBpbCIsInVpZCI6IlRaRE5SRiIsInNuIjoiQmhhcmR3YWoiLCJtYWlsIjoia2FwaWwuYmhhcmR3YWpAZ20uY29tIn0.bRgiJbdQjP3yosf7wNT40E-J3ibNHuYd-8iTqteX5fzIy8wRdpD_FzDDXlyxkZvnpU1sxF0pb_GwOrDczOzvFpE8Q6l1nVSx5sphfzFBEQ_HcUyGHjGXfLFwEOgvFmxCfPXSEKlkUf7B90BgJ1w7HuwYP7a-qZgD1Bh_sVymcaHW-ciTXHkq91FmikRDmGPZw9lzSMSMYlUPGnaUYIJ9EY_949SF-cXIEHtIchSA6xNsJmL1VYuKIcx24681D_0J2ZsBNUr4HkcKmlotJvQOER3nh2CW1HXJz094WR-4V3tvkAnO4NKe70oypPOH6_jl7pPLBe8Lp4Qxx-gh-F0QT';
        Onstar_Auth__c oaut = new Onstar_Auth__c(UserId__c=usrs[0].id, Access_Token__c = accesstokenstring);
        insert oaut;
     	String refreshtoken;
        SSOLogEnqueue sso = new SSOLogEnqueue(log);
        SSOLogEnqueue sso2 = new SSOLogEnqueue(accesstokenstring, refreshtoken,oaut.UserID__c);
        SSOLogEnqueue sso3 = new SSOLogEnqueue(authinfo);
        
		Test.startTest();
        System.enqueueJob(sso2);
        Test.stopTest();
    }
    
    static testmethod void testQueueableAuthinfo(){
     	String log ='amnsjd';
     	String name = 'amnsjd';
     	Onstar_Auth__c authinfo = new Onstar_Auth__c(UserId__c = '005Dn000006oRaaIAE');
     	String accesstoken = null;
     	String refreshtoken;
     	 List<Id> idLst = new List<Id>();
        for(Onstar_Auth__c objOuath : [SELECT Id, UserId__c FROM Onstar_Auth__c LIMIT 10]){
            idLst.add(objOuath.UserId__c);
        }
        List<User> usrs = [Select Id, Name from User WHERE ID NOT IN :idLst LIMIT 10];
        SSOLogEnqueue sso = new SSOLogEnqueue(accesstoken, refreshtoken, usrs[0].id);
       
        
		Test.startTest();
        System.enqueueJob(sso);
        Test.stopTest();
    }
    
    static testmethod void testQueueableSSOLog(){
     	String log ='amnsjd';
     	String name = 'amnsjd';
     	Onstar_Auth__c authinfo = null;
     	String accesstoken = null;
     	String refreshtoken;
         List<Id> idLst = new List<Id>();
        for(Onstar_Auth__c objOuath : [SELECT Id, UserId__c FROM Onstar_Auth__c LIMIT 10]){
            idLst.add(objOuath.UserId__c);
        }
        List<User> usrs = [Select Id, Name from User WHERE ID NOT IN :idLst LIMIT 10];
        
     	String userid = usrs[0].id;
        SSOLogEnqueue sso = new SSOLogEnqueue(accesstoken, refreshtoken, userid);
        
		Test.startTest();
        System.enqueueJob(sso);
        Test.stopTest();
    }
    
    static testmethod void testFuture(){
        
        List<Id> idLst = new List<Id>();
        for(Onstar_Auth__c objOuath : [SELECT Id, UserId__c FROM Onstar_Auth__c LIMIT 10]){
            idLst.add(objOuath.UserId__c);
        }
            List<User> usrs = [Select Id, Name from User WHERE ID NOT IN :idLst LIMIT 10];
      
        String a = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ii1LSTNROW5OUjdiUm9meG1lWm9YcWJIWkdldyIsImtpZCI6Ii1LSTNROW5OUjdiUm9meG1lWm9YcWJIWkdldyJ9.eyJhdWQiOiJhcGk6Ly9zZWMtYXV0aHotZ211c2VyLnBwLmdtLmNvbSIsImlzcyI6Imh0dHBzOi8vc3RzLndpbmRvd3MubmV0LzZiYWE0ZWIxLTEwNmEtNDQwYi1iNGY2LTUwMTM0NDk3ZDM2ZC8iLCJpYXQiOjE2ODk4NzE4NjAsIm5iZiI6MTY4OTg3MTg2MCwiZXhwIjoxNjg5ODc2ODM0LCJhY3IiOiIxIiwiYWlvIjoiQVZRQXEvOFRBQUFBelpOTlhXRTYvQ2hwNVNVOC9hK3k4ci9HL1p3bjZFRXE4bTZzWGtpUW4rdHFjNVNnQ085N2hzREIxUlNMNTNYY3NlMUV0WXFWejVoSU84TVUzWjBpeldCc0EweU5TRm94V3pCdEJYRXgweHM9IiwiYW1yIjpbInB3ZCIsIm1mYSJdLCJhcHBpZCI6IjNmOWM3YTY2LWM5YjEtNGRiZi05ODJjLThiM2E1MmEyOGQzYiIsImFwcGlkYWNyIjoiMSIsImZhbWlseV9uYW1lIjoiQmhhcmR3YWoiLCJnaXZlbl9uYW1lIjoiS2FwaWwiLCJpcGFkZHIiOiIxMDQuMTYxLjI0Ni4zOCIsIm5hbWUiOiJLYXBpbCBCaGFyZHdhaiAoQykiLCJvaWQiOiI3ODYxNDUxMS1mZmYxLTRlNDgtYmQ1MS0xNDJlYTYxOTY0ZmIiLCJvbnByZW1fc2lkIjoiUy0xLTUtMjEtMzQyOTAwODIwNS0xNTQ1MzUxMDQ2LTI3MDMzOTY2MzAtMTAyMjcyIiwicmgiOiIwLkFSSUFzVTZxYTJvUUMwUzA5bEFUUkpmVGJUa0JPTDdsc2FGTWdOdktlX1BScFhVU0FMby4iLCJyb2xlcyI6WyJvY3JtX2Nvbm5lY3RlZGFkdmlzb3IiLCIyMTkzMTVfT0NSTV9QUkVfUFJPRCJdLCJzY3AiOiJ1c2VyX2ltcGVyc29uYXRpb24iLCJzdWIiOiJkZEVlSGtqcmNSWFl4SXZzZkRnU2hRREZ0QldKUldtXzZURGxIX053dHN3IiwidGlkIjoiNmJhYTRlYjEtMTA2YS00NDBiLWI0ZjYtNTAxMzQ0OTdkMzZkIiwidW5pcXVlX25hbWUiOiJUWkROUkZAQVBBUUEuQ09SUFFBLkdFVUMuQ09SUC5HTS5DT00iLCJ1cG4iOiJUWkROUkZAQVBBUUEuQ09SUFFBLkdFVUMuQ09SUC5HTS5DT00iLCJ1dGkiOiIxUEgwTmlpN3BFQ0NObDlERHdnX0FBIiwidmVyIjoiMS4wIiwiZGlzcGxheU5hbWUiOiJLYXBpbCBCaGFyZHdhaiAoQykiLCJnaXZlbk5hbWUiOiJLYXBpbCIsInVpZCI6IlRaRE5SRiIsInNuIjoiQmhhcmR3YWoiLCJtYWlsIjoia2FwaWwuYmhhcmR3YWpAZ20uY29tIn0.bRgiJbdQjP3yosf7wNT40E-J3ibNHuYd-8iTqteX5fzIy8wRdpD_FzDDXlyxkZvnpU1sxF0pb_GwOrDczOzvFpE8Q6l1nVSx5sphfzFBEQ_HcUyGHjGXfLFwEOgvFmxCfPXSEKlkUf7B90BgJ1w7HuwYP7a-qZgD1Bh_sVymcaHW-ciTXHkq91FmikRDmGPZw9lzSMSMYlUPGnaUYIJ9EY_949SF-cXIEHtIchSA6xNsJmL1VYuKIcx24681D_0J2ZsBNUr4HkcKmlotJvQOER3nh2CW1HXJz094WR-4V3tvkAnO4NKe70oypPOH6_jl7pPLBe8Lp4Qxx-gh-F0QT';
       Onstar_Auth__c oaut = new Onstar_Auth__c(UserId__c=usrs[0].id, Access_Token__c = a);
        insert oaut;
       
    	String b = '';
        String c = oaut.UserId__c;
        Test.startTest();
        SSOLogEnqueue.updateTokenInfo(a,b,c);
        Test.stopTest();
    }

}