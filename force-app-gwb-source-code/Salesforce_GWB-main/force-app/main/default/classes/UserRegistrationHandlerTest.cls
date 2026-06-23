@isTest
private class UserRegistrationHandlerTest {
    
    @IsTest
    static void testCreateAndUpdateUser() {
        Test.startTest();
        Profile p = [SELECT Id FROM Profile WHERE Name='GM Base User']; 
        User u = new User(Alias = 'testId', Email='b2btestuser@testorg.com', FirstName='b2b',
                          EmailEncodingKey='UTF-8', LastName='Testing', LanguageLocaleKey='en_US', 
                          LocaleSidKey='en_US', ProfileId = p.Id, 
                          TimeZoneSidKey='America/Los_Angeles', UserName='b2btestuser@testorg.com', FederationIdentifier='ABCD');
        insert u;
        
        UserRegistrationHandler handler = new UserRegistrationHandler();
        
        Map<String,String> mapUserAttributes = new Map<String,String>();
        mapUserAttributes.put('access_token', 'TestAccessToken');
        mapUserAttributes.put('id_token','TestIdToken');
        mapUserAttributes.put('user_roles', 'TestUserRole');
        mapUserAttributes.put('auth_code', 'TestAuthCode');
        mapUserAttributes.put('refresh_token', 'TestRefreshToken');
        
        Auth.UserData sampleData = new Auth.UserData( u.FederationIdentifier, u.FirstName, u.LastName, u.FirstName , u.Email, '', u.Username, 
                                                     'fr_CA', '', '', mapUserAttributes);
        
        try{
            User testuser = handler.createUser(null, sampleData);
            handler.updateUser(u.Id, null, sampleData);
        }catch(Exception e){
            System.debug('Exception occurred in testCreateAndUpdateUser '+e.getMessage());
        }    
        Test.stopTest();
        User newuser = [Select Id,FederationIdentifier,LocaleSidKey From User where FederationIdentifier='ABCD'];
        System.debug('newuser <<< '+newuser);
        System.assert(newUser !=null,'The User Should not be null');
        System.assert('en_US'.equalsIgnorecase(newUser.LocaleSidKey),'The Locale should not be updated');
    }
    
       @IsTest
       static void testCreateNewGWBUser() {
        UserRegistrationHandler handler = new UserRegistrationHandler();
        Test.startTest();
        Map<String,String> mapUserAttributes = new Map<String,String>();
        mapUserAttributes.put('access_token', 'TestAccessToken');
        mapUserAttributes.put('id_token','TestIdToken');
        mapUserAttributes.put('user_roles', 'TestUserRole');
        mapUserAttributes.put('auth_code', 'TestAuthCode');
        mapUserAttributes.put('refresh_token', 'TestRefreshToken');
        mapUserAttributes.put('gm_id', 'YZTRGY');
        mapUserAttributes.put('user_roles', '(Central_Global_Admin)'); 
        Auth.UserData sampleData = new Auth.UserData('ABCD','b2b', 'Testing', 'b2b' , 'b2btestuser@testorg.com', '','b2btestuser@testorg.com', 
                                                     'en_US', '', '', mapUserAttributes);
        
        try{
            User testuser = handler.createUser(null, sampleData);
        }catch(Exception e){
            System.debug('Exception occurred in testCreateNewGWBUser '+e.getMessage());
        } 
        Test.stopTest();
        User newuser = [Select Id,CommunityNickName From User where FederationIdentifier='YZTRGY'];
        System.assert(newUser !=null,'The User Should not be null');
    }
    
    //    @IsTest
    //    static void testCreateKMUserWithNoKMProfile() {
    //     kmusers_profile__c setting = new kmusers_profile__c();
	// 	setting.profile__c = 'Read Only';
	// 	insert setting;     
    //     UserRegistrationHandler handler = new UserRegistrationHandler();
    //     Test.startTest();
    //     Map<String,String> mapUserAttributes = new Map<String,String>();
    //     mapUserAttributes.put('access_token', 'TestAccessToken');
    //     mapUserAttributes.put('id_token','TestIdToken');
    //     mapUserAttributes.put('user_roles', 'TestUserRole');
    //     mapUserAttributes.put('auth_code', 'TestAuthCode');
    //     mapUserAttributes.put('refresh_token', 'TestRefreshToken');
    //     mapUserAttributes.put('gm_id', 'YZTRGY');
    //     mapUserAttributes.put('gmin', '309877654'); 
    //     mapUserAttributes.put('user_roles', '(ocrm_ses_advisor, ocrm_admin)'); 
    //     Auth.UserData sampleData = new Auth.UserData('ABCD','b2b', 'Testing', 'b2b' , 'b2btestuser@testorg.com', '','b2btestuser@testorg.com', 
    //                                                  'en_US', '', '', mapUserAttributes);
        
    //     try{
    //         User testuser = handler.createUser(null, sampleData);
    //     }catch(Exception e){
    //      System.debug('Exception occurred in testCreateKMUserWithNoKMProfile '+e.getMessage());
    //     } 
    //     Test.stopTest();
    //     List<User> newusers = [Select Id From User where FederationIdentifier='YZTRGY'];
    //     System.assert((newusers ==null || newusers.isEmpty()),'The User Should be null');
    // }
    //    @IsTest
    //    static void testCreateKMUserWithNoProfile() {
    //     UserRegistrationHandler handler = new UserRegistrationHandler();
    //     Test.startTest();
    //     Map<String,String> mapUserAttributes = new Map<String,String>();
    //     mapUserAttributes.put('access_token', 'TestAccessToken');
    //     mapUserAttributes.put('id_token','TestIdToken');
    //     mapUserAttributes.put('user_roles', 'TestUserRole');
    //     mapUserAttributes.put('auth_code', 'TestAuthCode');
    //     mapUserAttributes.put('refresh_token', 'TestRefreshToken');
    //     mapUserAttributes.put('gm_id', 'YZTRGY');
    //     mapUserAttributes.put('user_roles', 'Central_Global_Admin'); 
    //     Auth.UserData sampleData = new Auth.UserData('ABCD','b2b', 'Testing', 'b2b' , 'b2btestuser@testorg.com', '','b2btestuser@testorg.com', 
    //                                                  'en_US', '', '', mapUserAttributes);
        
    //     try{
    //         User testuser = handler.createUser(null, sampleData);
    //     }catch(Exception e){
    //      System.debug('Exception occurred in testCreateKMUserWithNoKMProfile '+e.getMessage());
    //     } 
    //     Test.stopTest();
    //     List<User> newusers = [Select Id From User where FederationIdentifier='YZTRGY'];
    //     System.assert(newusers.isEmpty(),'The User Should be null');
    // }

    
}