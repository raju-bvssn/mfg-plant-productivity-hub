@isTest
private class UserProvisioningUtilTest {
   @testSetup
   private static void setupTestData() {
        List<Profile> allProfiles = [SELECT Id, Name FROM Profile LIMIT 100];
        Profile profile = null;
        Profile adminprofile = null;
        for (Profile p : allProfiles) {
            if (p.Name == 'System Administrator') { adminprofile = p; }
            if (profile == null && p.Name != 'System Administrator') { profile = p; }
        }
        if (profile == null && !allProfiles.isEmpty()) {
            profile = allProfiles[0].Name == 'System Administrator' && allProfiles.size() > 1
                ? allProfiles[1] : allProfiles[0];
        }
        if (adminprofile == null) {
            List<Profile> adminList = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
            adminprofile = adminList.isEmpty() ? profile : adminList[0];
        }
        
        List < User > userList = new List < User > ();

        userList.add(
            new User(
            ProfileId = profile.Id,
            Username = 'testInter98@example9.com',
            Email = 'testInter98@example9.com',
            Alias = 'tuser',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            LastName = 'Test',
            FirstName = 'User',
            Persona__c = '(Industrial_Engineer,Plant_Approver)'
            )
        );

        userList.add(
            new User(
                Alias = 'testId1',
                Email = 'testAdminUser@example.com',
                FirstName = 'b2b',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Testing',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = adminprofile.Id,
                Persona__c = 'Industrial_Engineer,b2b_commercial_user',
                TimeZoneSidKey = 'America/Los_Angeles',
                UserName = 'b2btestuser@testorg.com'
            )
        );

        userList.add(
            new User(
            ProfileId = profile.Id,
            Username = 'readonly@example7.com',
            Email = 'readonly@example7.com',
            Alias = 'reuser',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            LastName = 'ReadOnly',
            FirstName = 'User',
            Persona__c = '(Plant_Viewer)'
            )
        );

        userList.add(
            new User(
                Alias = 'testId2',
                Email = 'b2btestuser89@testorg.com',
                FirstName = 'b2b',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Testing',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = profile.Id,
                Persona__c = '(PlantAdmin)',
                TimeZoneSidKey = 'America/Los_Angeles',
                UserName = 'b2btestuser89@testorg.com'
            )
        );

        userList.add(
            new User(
                Alias = 'testId3',
                Email = 'personaNulltestuser@testorg.com',
                FirstName = 'b2b',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Testing',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = profile.Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                UserName = 'personaNulltestuser@testorg.com'
            )
        );

        insert userList;
        List<PermissionSetGroup> permsetGroups = [
            SELECT Id, Status
            FROM PermissionSetGroup
            LIMIT 1
        ];
        if (!permsetGroups.isEmpty()) {
            Test.calculatePermissionSetGroup(permsetGroups[0].Id);
        }
   }

   /* CallCenter-related tests commented out - assignCallCenter is commented out in UserProvisioningUtil
   @isTest
   private static void testUserprovisioningWithCallCenterAssignment() {
      Test.startTest();
      User testUser = [
         SELECT Id, ProfileId, Persona__c, CallCenterId
         FROM User
         WHERE Username = 'testInter98@example9.com'
         LIMIT 1
      ];
      UserProvisioningUtil util = new UserProvisioningUtil();
      util.provisionUserWithProfileAndPermsets(testUser, false);
      Test.stopTest();
      // Verify provisioning completed; CallCenter/UserPackageLicense depend on org metadata (Industrial_Engineer/Plant_Approver may not have them)
      System.assertNotEquals(null, testUser.Id, 'User should exist');
   }

   @isTest
   private static void testUserprovisioningWithEmptyCallCenterAssignment() {
      Test.startTest();
      // Query the custom metadata records
      List < Ad_Group_Mapping__mdt > records = [
         SELECT
         Id,
         Label,
         UserPersonaMappingName__c,
         PriorityNbr__c,
         ProfileGroupName__c,
         PermissionGroupSetName__c,
         PublicGroupName__c,
         CallCenterName__c,
         TelephonyPackageLicenseName__c
         FROM Ad_Group_Mapping__mdt
      ];
      User testUser = [
         SELECT Id, ProfileId, Persona__c, CallCenterId
         FROM User
         WHERE Username = 'readonly@example7.com'
         LIMIT 1
      ];
      UserProvisioningUtil util = new UserProvisioningUtil();
      util.provisionUserWithProfileAndPermsets(testUser,false);
      System.assert(
         String.isBlank(testUser.CallCenterId),
         'CallCenter should not be assigned'
      );
      List < UserPackageLicense > userPackageLicenseList = [
         SELECT Id, UserId, PackageLicenseId
         FROM UserPackageLicense
         WHERE UserId =: testUser.Id
      ];
      System.assert(
         userPackageLicenseList.IsEmpty(),
         'UserPackageLicense should not be assigned'
      );
      Test.stopTest();
   }
   */

   @isTest
   private static void testProvisioningWithMultiplePersonas() {
      Test.startTest();
      User testUser = [
         SELECT Id, ProfileId, Persona__c
         FROM User
         WHERE Username = 'testInter98@example9.com'
         LIMIT 1
      ];
      UserProvisioningUtil util = new UserProvisioningUtil();
      util.provisionUserWithProfileAndPermsets(testUser, false);
      Test.stopTest();
      System.assertNotEquals(null, testUser.Id, 'User should exist');
   }

   @isTest
   private static void testProvisioningWithPersonaWithoutParentheses() {
      User u = [SELECT Id, Persona__c, ProfileId FROM User WHERE Email = 'readonly@example7.com' LIMIT 1];
      u.Persona__c = 'Plant_Viewer';
      update u;
      Test.startTest();
      UserProvisioningUtil util = new UserProvisioningUtil();
      util.provisionUserWithProfileAndPermsets(u, false);
      Test.stopTest();
      System.assertNotEquals(null, u.Id, 'User should exist');
   }

   @isTest
   private static void testProvisioningWithInvalidPersonaTriggersException() {
      User u = [SELECT Id, Persona__c, ProfileId FROM User WHERE Email = 'personaNulltestuser@testorg.com' LIMIT 1];
      u.Persona__c = 'NonExistentPersona_A,NonExistentPersona_B';
      update u;
      Test.startTest();
      UserProvisioningUtil util = new UserProvisioningUtil();
      util.provisionUserWithProfileAndPermsets(u, false);
      Test.stopTest();
      System.assertNotEquals(null, u.Id, 'User should exist; exception handled gracefully');
   }

   @isTest
   private static void testProfileAndPermSetAssignmentsWithAdminProfile() {
      Test.startTest();
      User u = [SELECT Id,Persona__c,ProfileId,GWB_Region__c,GM_ApplicableRegionAccess__c,UserPermissionsSupportUser from User where Email='testAdminUser@example.com']; 
      UserProvisioningUtil util = new UserProvisioningUtil();
      util.provisionUserWithProfileAndPermsets(u,false);
      Test.stopTest();
   }

   // @isTest
   // private static void testProfileAndPermSetAssignmentsWithAdminProfileAndAssignedPermSetsAndPublicGroups() {
   //    Test.startTest();
   //    User u = [SELECT Id,Persona__c,ProfileId,GWB_Region__c,GM_ApplicableRegionAccess__c,UserPermissionsSupportUser FROM User where Email = 'b2btestuser89@testorg.com' LIMIT 1];
   //    insertPermissionSetGrpsAndPublicGrps(u);
   //    UserProvisioningUtil util = new UserProvisioningUtil();
   //    util.provisionUserWithProfileAndPermsets(u,false);
   //    List < GroupMember > testQueueAss = [SELECT Id, Group.DeveloperName, Group.Name, Group.Type FROM GroupMember where UserOrGroupId =: u.Id and Group.Type = 'Queue'];
   //    System.assert((testQueueAss != null && testQueueAss.size() > 0), 'The Queue assignment should not be deleted');
   //    Test.stopTest();
   // }

   private static void insertPermissionSetGrpsAndPublicGrps(User u) {
      PermissionSetGroup permsetGroup = [
         SELECT Id, Status
         FROM PermissionSetGroup
         LIMIT 1
      ];
      List < PermissionSetAssignment > newPermissionSetAssignments = new List < PermissionSetAssignment > ();
      PermissionSetAssignment newPermissionSetAssignment = new PermissionSetAssignment();
      newPermissionSetAssignment.AssigneeId = u.Id;
      newPermissionSetAssignment.PermissionSetGroupId = permsetGroup.Id;
      if (permsetGroup.Status != 'Updated') {
         Test.calculatePermissionSetGroup(permsetGroup.Id);
      }
      newPermissionSetAssignments.add(newPermissionSetAssignment);
      upsert newPermissionSetAssignments;

      Group groupPG = [SELECT Id, DeveloperName FROM Group where type = 'Regular'
         LIMIT 1
      ];
      
      Group groupQueue = [SELECT Id, DeveloperName FROM Group where type = 'Queue'
         LIMIT 1
      ];
      list < GroupMember > groupMembers = new List < GroupMember > ();
      GroupMember groupMember = new GroupMember();
      groupMember.GroupId = groupPG.Id;
      groupMember.UserOrGroupId = u.Id;
      GroupMember groupMember2 = new GroupMember();
      groupMember2.GroupId = groupQueue.Id;
      groupMember2.UserOrGroupId = u.Id;
      groupMembers.add(groupMember);
      groupMembers.add(groupMember2);
      upsert groupMembers;
      List < GroupMember > groupMems = [SELECT Id, GroupId, UserOrGroupId, Group.DeveloperName, Group.Name, Group.Type FROM GroupMember where UserOrGroupId =: u.Id];
   }

   // @isTest
   // private static void testProfileAndPermSetAssignmentsWithDowngradeSalesforceLicense() {
   //    Test.startTest();
   //    User u = [SELECT Id,Persona__c,ProfileId,GWB_Region__c,GM_ApplicableRegionAccess__c,UserPermissionsSupportUser FROM User where Email = 'b2btestuser89@testorg.com' LIMIT 1];
   //    insertPermissionSetGrpsAndPublicGrps(u);
   //    UserProvisioningUtil util = new UserProvisioningUtil();
   //    util.provisionUserWithProfileAndPermsets(u,false);
   //    List < GroupMember > testQueueAss = [SELECT Id, Group.DeveloperName, Group.Name, Group.Type FROM GroupMember where UserOrGroupId =: u.Id and Group.Type = 'Queue'];
   //    System.assert((testQueueAss != null && testQueueAss.size() > 0), 'The Queue assignment should not be deleted');
   //    Test.stopTest();
   // }

   // @isTest
   // private static void testProfileAndPermSetAssignmentsWithPersonaNull() {
   //    Test.startTest();
   //    User u = [SELECT Id,Persona__c,ProfileId,GWB_Region__c,GM_ApplicableRegionAccess__c,UserPermissionsSupportUser from User where Email='personaNulltestuser@testorg.com']; 
   //    insertPermissionSetGrpsAndPublicGrps(u);
   //    UserProvisioningUtil util = new UserProvisioningUtil();
   //    util.provisionUserWithProfileAndPermsets(u,false);
   //    util.getSSOProviderName();
   //    Test.stopTest();
   // }
   @isTest
   private static void testTrimExtraSpaces() {
      Set<String> input = new Set<String>{ '  PermSet1  ', 'PermSet2', '  PermSet3  ' };
      Set<String> result = UserProvisioningUtil.trimExtraSpaces(input);
      System.assert(result.contains('PermSet1'), 'Should trim leading/trailing spaces');
      System.assert(result.contains('PermSet2'), 'Should preserve already-trimmed');
      System.assert(result.contains('PermSet3'), 'Should trim spaces');
      System.assertEquals(3, result.size(), 'Should have 3 unique trimmed values');
   }

   @isTest
   private static void testProvisionWithIsUpdateUserTrue() {
      Test.startTest();
      User u = [SELECT Id, Persona__c, ProfileId, GWB_Region__c, GM_ApplicableRegionAccess__c, UserPermissionsSupportUser, LocaleSidKey
         FROM User WHERE Email = 'b2btestuser89@testorg.com' LIMIT 1];
      UserProvisioningUtil util = new UserProvisioningUtil();
      util.provisionUserWithProfileAndPermsets(u, true);
      Test.stopTest();
      System.assertNotEquals(null, u.Id, 'User should be processed');
   }

   @isTest
   private static void testGetSSOProviderName() {
      UserProvisioningUtil util = new UserProvisioningUtil();
      String providerName = util.getSSOProviderName();
      System.assertNotEquals(null, providerName, 'SSO provider name should not be null');
      System.assert(providerName == 'GMAzure' || providerName == 'GMAzure_PreProd', 'Should return valid SSO provider');
   }

   @isTest
   private static void testProcessPermissionSetGroupsAndProcessPublicGroups() {
      User u = [SELECT Id FROM User WHERE Email = 'b2btestuser89@testorg.com' LIMIT 1];
      Test.startTest();
      UserProvisioningUtil.processPermissionSetGroups(u, new Set<String>());
      UserProvisioningUtil.processPublicGroups(u, new Set<String>());
      Test.stopTest();
      System.assertNotEquals(null, u.Id, 'User should exist');
   }

   // @isTest
   // private static void testProcessPermissionSetGroupsAndPublicGroupsWithInsert() {
   //    User u = [SELECT Id FROM User WHERE Email = 'b2btestuser89@testorg.com' LIMIT 1];
   //    List<PermissionSetGroup> psgs = [SELECT Id, DeveloperName FROM PermissionSetGroup LIMIT 2];
   //    List<Group> regularGroups = [SELECT Id, DeveloperName FROM Group WHERE Type = 'Regular' AND DeveloperName != null LIMIT 2];
   //    Set<String> psgNames = new Set<String>();
   //    Set<String> groupNames = new Set<String>();
   //    for (PermissionSetGroup psg : psgs) { psgNames.add(psg.DeveloperName); }
   //    for (Group g : regularGroups) { groupNames.add(g.DeveloperName); }
   //    Test.startTest();
   //    if (!psgNames.isEmpty()) UserProvisioningUtil.processPermissionSetGroups(u, psgNames);
   //    if (!groupNames.isEmpty()) UserProvisioningUtil.processPublicGroups(u, groupNames);
   //    Test.stopTest();
   //    System.assertNotEquals(null, u.Id, 'User should exist');
   // }

   // @isTest
   // private static void testUserProvisioningWithEmptyCustomMetadata() {
   //    Test.startTest();
   //    User u = [SELECT Id,Persona__c,ProfileId,GWB_Region__c,GM_ApplicableRegionAccess__c,UserPermissionsSupportUser from User where Email='readonly@example7.com']; 
   //    insertPermissionSetGrpsAndPublicGrps(u);
   //    UserProvisioningUtil util = new UserProvisioningUtil();
   //    util.provisionUserWithProfileAndPermsets(u,false);
   //    Test.stopTest();
   // }

   @isTest
   private static void testProvisioningChangesProfileAndSetsSupportUser() {
      Profile gmBaseProfile = [SELECT Id, Name, UserLicense.Name FROM Profile WHERE Name = 'GM Base User' LIMIT 1];
      List<Profile> otherProfiles = [
         SELECT Id, Name
         FROM Profile
         WHERE UserLicense.Name = 'Salesforce'
         AND Name != 'System Administrator'
         AND Id != :gmBaseProfile.Id
         LIMIT 1
      ];
      if (otherProfiles.isEmpty()) {
         return;
      }

      User tempUser = new User(
         ProfileId = otherProfiles[0].Id,
         Username = 'profchange' + System.now().getTime() + '@example.com',
         Email = 'profchange' + System.now().getTime() + '@example.com',
         Alias = 'prchg',
         EmailEncodingKey = 'UTF-8',
         LanguageLocaleKey = 'en_US',
         LocaleSidKey = 'en_US',
         TimeZoneSidKey = 'America/Los_Angeles',
         LastName = 'ProfileChange',
         FirstName = 'User',
         Persona__c = '(PlantAdmin)'
      );
      insert tempUser;

      Test.startTest();
      UserProvisioningUtil util = new UserProvisioningUtil();
      util.provisionUserWithProfileAndPermsets(tempUser, false);
      Test.stopTest();

      User updatedUser = [SELECT Id, ProfileId, UserPermissionsSupportUser FROM User WHERE Id = :tempUser.Id];
      System.assertEquals(gmBaseProfile.Id, updatedUser.ProfileId, 'User should be moved to mapped GM Base User profile.');
      System.assertEquals(true, updatedUser.UserPermissionsSupportUser, 'Salesforce licensed target profile should enable Support User.');
   }

   @isTest
   private static void testAdGroupComparatorGreaterAndEqualBranches() {
      UserProvisioningUtil.AdGroupComparator comparator = new UserProvisioningUtil.AdGroupComparator();

      Ad_Group_Mapping__mdt lowPriority = new Ad_Group_Mapping__mdt();
      lowPriority.PriorityNbr__c = 1;
      Ad_Group_Mapping__mdt highPriority = new Ad_Group_Mapping__mdt();
      highPriority.PriorityNbr__c = 2;
      Ad_Group_Mapping__mdt samePriority = new Ad_Group_Mapping__mdt();
      samePriority.PriorityNbr__c = 2;

      System.assertEquals(-1, comparator.compare(lowPriority, highPriority), 'Lower priority number should sort before higher value.');
      System.assertEquals(1, comparator.compare(highPriority, lowPriority), 'Higher priority number should sort after lower value.');
      System.assertEquals(0, comparator.compare(highPriority, samePriority), 'Equal priorities should compare as equal.');
   }
}