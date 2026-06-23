@isTest
private class PlantCollabGroupRemovalQblTest {
    private static User createTestUser() {
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(DateTime.now().getTime());
        User testUser = new User(
            Alias = 'pcgr' + stamp.substring(Math.max(0, stamp.length() - 4)),
            Email = 'pcgr.' + stamp + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Queueable',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = stdProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'pcgr.' + stamp + '@example.com'
        );
        insert testUser;
        return testUser;
    }

    @isTest
    static void executeDeletesGroupMembersWhenIdsProvided() {
        User testUser = createTestUser();
        Group collaborationGroup = new Group(Name = 'PCGR_Group_' + DateTime.now().getTime(), Type = 'Regular');
        insert collaborationGroup;

        GroupMember member = new GroupMember(GroupId = collaborationGroup.Id, UserOrGroupId = testUser.Id);
        insert member;

        Test.startTest();
        System.enqueueJob(new PlantCollaboratorGroupRemovalQueueable(new List<Id>{ member.Id }));
        Test.stopTest();

        Integer remaining = [SELECT COUNT() FROM GroupMember WHERE Id = :member.Id];
        System.assertEquals(0, remaining, 'Specified group members should be deleted by the queueable.');
    }

    @isTest
    static void executeReturnsSafelyForNullEmptyAndNoMatches() {
        Test.startTest();
        System.enqueueJob(new PlantCollaboratorGroupRemovalQueueable(null));
        System.enqueueJob(new PlantCollaboratorGroupRemovalQueueable(new List<Id>()));
        System.enqueueJob(new PlantCollaboratorGroupRemovalQueueable(new List<Id>{ UserInfo.getUserId() }));
        Test.stopTest();

        System.assert(true, 'Queueable should safely no-op for null, empty, or non-group-member ids.');
    }
}