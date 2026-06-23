/**
 * @description Handler class for Plant_Collaborator__c trigger.
 */
public class PlantCollaboratorTriggerHandler {
    /**
     * @description Main handler method for Plant_Collaborator__c deletion.
     * @param oldRecords List of deleted Plant_Collaborator__c records
     */
    public static void handleAfterDelete(List<Plant_Collaborator__c> oldRecords) {
        if (oldRecords.isEmpty()) return;
        
        Set<Id> plantIds = new Set<Id>();
        
        for (Plant_Collaborator__c pc : oldRecords) {
            if (pc.Plant__c != null) {
                plantIds.add(pc.Plant__c);
            }
        }
        
        Map<Id, Plant__c> plantMap = new Map<Id, Plant__c>(
            [
                SELECT Id, Name
                FROM Plant__c
                WHERE Id IN :plantIds
            ]
        );
        
        Set<String> groupNames = new Set<String>();
        Set<Id> userIds = new Set<Id>();
        
        Map<String, String> userToGroupNameMap = new Map<String, String>();
        
        for (Plant_Collaborator__c pc : oldRecords) {
            Plant__c plantRec = plantMap.get(pc.Plant__c);
            
            if (pc.User__c == null || plantRec == null || String.isBlank(plantRec.Name)) continue;
            
            String formattedPlantName = plantRec.Name.replace(' ', '_');

            String groupName;
            
            if (pc.Access_Level__c == 'Read Only') {
                groupName = formattedPlantName + '_R';
            }
            else if (pc.Access_Level__c == 'Read/Edit') {
                groupName = formattedPlantName + '_RW';
            }
            
            if (String.isNotBlank(groupName)) {
                groupNames.add(groupName);
                userIds.add(pc.User__c);
                
                userToGroupNameMap.put(
                    pc.User__c,
                    groupName
                );
            }
        }
        
        if (groupNames.isEmpty() || userIds.isEmpty()) return;
        
        Map<String, Id> groupNameToIdMap = new Map<String, Id>();

        for (Group grp : [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Regular'
            AND Name IN :groupNames
        ]) {
            
            groupNameToIdMap.put(grp.Name,grp.Id);
        }
        
        if (groupNameToIdMap.isEmpty()) return;
        
        List<GroupMember> existingMembers = [SELECT Id, GroupId, UserOrGroupId FROM GroupMember
                                             WHERE UserOrGroupId IN :userIds AND GroupId IN :groupNameToIdMap.values()];
        
        Set<Id> groupMemberIdsToDelete = new Set<Id>();
        
        for (GroupMember gm : existingMembers) {

            String expectedGroupName = userToGroupNameMap.get((Id)gm.UserOrGroupId);

            Id expectedGroupId = groupNameToIdMap.get(expectedGroupName);

            if (gm.GroupId == expectedGroupId) {
                groupMemberIdsToDelete.add(gm.Id);
            }
        }
        
        /*
         * Queueable Call
         */
        if (!groupMemberIdsToDelete.isEmpty()) {

            System.enqueueJob(
                new PlantCollaboratorGroupRemovalQueueable(
                    new List<Id>(groupMemberIdsToDelete)
                )
            );
        }
    }

}