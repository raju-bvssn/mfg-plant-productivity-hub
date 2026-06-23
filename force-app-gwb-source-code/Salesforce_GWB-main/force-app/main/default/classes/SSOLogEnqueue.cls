public class SSOLogEnqueue implements Queueable, Database.AllowsCallouts{
    private String log;
    private String name;
    private Onstar_Auth__c authinfo;
    private String strAccessToken;
    private String strRefreshToken;
    private String currentUserId;
    
    public SSOLogEnqueue(String log){
        this.log = log;
    }
    public SSOLogEnqueue(Onstar_Auth__c authinfo){
        this.authinfo = authinfo;
    }
    
    public SSOLogEnqueue(String accesstoken, String refreshtoken, String userid) {
        this.strAccessToken = accesstoken;
        this.strRefreshToken = strRefreshToken;
        this.currentuserid = userid;
    }
    
    public void execute(QueueableContext context) {
        if(this.strAccessToken != null){
            Onstar_Auth__c onstarauth = [select id, Access_Token__c, Refresh_Token__c, UserId__c from Onstar_Auth__c where UserId__c =: this.currentuserid][0];
            if(onstarauth != null){
                onstarauth.Access_Token__c = this.strAccessToken;
                onstarauth.Refresh_Token__c = this.strRefreshToken;
                upsert onstarauth onstarauth.UserID__c;
            }
        }
        else if(this.authinfo!= null){
            upsert this.authinfo this.authinfo.UserID__c;
        }else{
            SSOLog__c  a = new SSOLog__c();
            a.name = String.valueOf(System.now());
            a.Log__c = this.log;
            insert a;  
        }
    }
    
    @future 
    public static void updateTokenInfo(String a, String b, String c) {
        System.debug('Method called with: ' + a + ' and ' + b);
        // Perform long-running code
        Onstar_Auth__c onstarauth = [select id, Access_Token__c, Refresh_Token__c, UserId__c from Onstar_Auth__c where UserId__c =: c][0];
        if(onstarauth != null){
            onstarauth.Access_Token__c = a;
            onstarauth.Refresh_Token__c = b;
            upsert onstarauth onstarauth.UserID__c;
        }
    }
    
    
}