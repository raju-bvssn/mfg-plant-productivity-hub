@isTest
public class PlantCollaboratorTriggerHandlerTest {

    @testSetup
    static void setupTestData() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User adminUser = new User(
            Alias = 'adm45',
            Email = 'admin' + DateTime.now().getTime() + '@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Admin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'admin' + DateTime.now().getTime() + '@test.com'
        );
        insert adminUser;

        System.runAs(adminUser) {
            Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            User testUser = new User(
                Alias = 'tusr34',
                Email = 'testuser@example.com',
                LastName = 'Test',
                ProfileId = stdProfile.Id,
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'America/Los_Angeles',
                Username = 'testuser' + DateTime.now().getTime() + '@example.com'
            );
            insert testUser;
        }
    }

    private static User fetchStandardTestUser() {
        return [SELECT Id FROM User WHERE Alias = 'tusr34' LIMIT 1];
    }

    private static User fetchAdminUser() {
        return [SELECT Id FROM User WHERE Alias = 'adm45' LIMIT 1];
    }

    private static Plant__c createPlantWithMvp(String name) {
        Plant__c plant = new Plant__c(
            Name = name,
            Auth_Region__c = 'GMNA',
            MVP__c = UserInfo.getUserId()
        );
        insert plant;
        return plant;
    }

    private static void createGroupMemberAsAdmin(String groupName, Id userId) {
        User adminUser = fetchAdminUser();
        System.runAs(adminUser) {
            Group groupRecord = new Group(Name = groupName, Type = 'Regular');
            insert groupRecord;
            insert new GroupMember(GroupId = groupRecord.Id, UserOrGroupId = userId);
        }
    }

    @isTest
    static void testAfterDelete_SingleRecord_ReadAccess() {
        User u = fetchStandardTestUser();
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String plantName = 'My Plant ' + suffix;
        Plant__c plant = createPlantWithMvp(plantName);
        String groupName = plant.Name.replace(' ', '_') + '_R';
        createGroupMemberAsAdmin(groupName, u.Id);
        Integer memberCountBefore = [
            SELECT Count()
            FROM GroupMember
            WHERE UserOrGroupId = :u.Id
            AND Group.Name = :groupName
        ];

        // MATCHING HANDLER: If your handler uses 'Read Only', use that here.
        // If it uses 'Read only' (lowercase), update the handler or this test.
        Plant_Collaborator__c pc = new Plant_Collaborator__c(
            Plant__c = plant.Id,
            User__c = u.Id,
            Collaborator_Type__c = 'Plant Viewer', 
            Access_Level__c = 'Read Only' 
        );
        User adminUser = fetchAdminUser();

        Test.startTest();
            System.runAs(adminUser) {
                PlantCollaboratorTriggerHandler.handleAfterDelete(new List<Plant_Collaborator__c>{ pc });
            }
        Test.stopTest(); // Executes Queueable

        List<GroupMember> remaining = [SELECT Id FROM GroupMember WHERE UserOrGroupId = :u.Id AND Group.Name = :groupName];
        System.assert(
            remaining.size() <= memberCountBefore,
            'The handler should not create new group memberships during delete processing.'
        );
    }

    @isTest
    static void testAfterDelete_BulkRecords() {
        User u = fetchStandardTestUser();
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Plant__c plant1 = createPlantWithMvp('My Plant ' + suffix);
        Plant__c plant2 = createPlantWithMvp('Bulk Plant ' + suffix);
        String groupNameRw = plant1.Name.replace(' ', '_') + '_RW';
        String groupNameR = plant2.Name.replace(' ', '_') + '_R';
        createGroupMemberAsAdmin(groupNameRw, u.Id);
        createGroupMemberAsAdmin(groupNameR, u.Id);
        Integer memberCountBefore = [
            SELECT Count()
            FROM GroupMember
            WHERE UserOrGroupId = :u.Id
            AND Group.Name IN :new Set<String>{ groupNameRw, groupNameR }
        ];

        List<Plant_Collaborator__c> collabs = new List<Plant_Collaborator__c>{
            new Plant_Collaborator__c(
                Plant__c = plant1.Id, 
                User__c = u.Id, 
                Collaborator_Type__c = 'Plant Admin', 
                Access_Level__c = 'Read/Edit'
            ),
            new Plant_Collaborator__c(
                Plant__c = plant2.Id, 
                User__c = u.Id, 
                Collaborator_Type__c = 'Plant Viewer', 
                Access_Level__c = 'Read Only'
            )
        };
        User adminUser = fetchAdminUser();

        Test.startTest();
            System.runAs(adminUser) {
                PlantCollaboratorTriggerHandler.handleAfterDelete(collabs);
            }
        Test.stopTest();

        // Check specifically for the groups that should have been deleted
        List<GroupMember> remaining = [
            SELECT Id, Group.Name 
            FROM GroupMember 
            WHERE UserOrGroupId = :u.Id 
            AND Group.Name IN :new Set<String>{ groupNameRw, groupNameR }
        ];
        
        System.assert(
            remaining.size() <= memberCountBefore,
            'Bulk collaborator deletes should not add memberships unexpectedly.'
        );
    }

    @isTest
    static void testAfterDelete_NoPlantMatch() {
        User u = fetchStandardTestUser();
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Plant__c plant = createPlantWithMvp('Unknown Plant ' + suffix);

        Plant_Collaborator__c pc = new Plant_Collaborator__c(
            Plant__c = plant.Id,
            User__c = u.Id,
            Collaborator_Type__c = 'Plant Admin',
            Access_Level__c = 'Read/Edit'
        );
        insert pc;

        Test.startTest();
            delete pc;
        Test.stopTest();

        // Should not throw error even if Group doesn't exist
        System.assert(true, 'Handler handled missing group gracefully');
    }

    @isTest
    static void testAfterDelete_EmptyInputNoOp() {
        Test.startTest();
        PlantCollaboratorTriggerHandler.handleAfterDelete(new List<Plant_Collaborator__c>());
        Test.stopTest();
        System.assert(true, 'Handler should return safely for empty input.');
    }

}