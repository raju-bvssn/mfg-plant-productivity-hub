/**
 * @description Queueable method to delete group members.
 * The queueable is triggered by Plant_Collaborator__c trigger handler.
 */
public class PlantCollaboratorGroupRemovalQueueable implements Queueable{
    
    private List<Id> groupMemberIds;
    
    public PlantCollaboratorGroupRemovalQueueable(List<Id> groupMemberIds) {
        this.groupMemberIds = groupMemberIds;
    }
    
    public void execute(QueueableContext context) {
        if (groupMemberIds == null || groupMemberIds.isEmpty()) return;
        
        List<GroupMember> membersToDelete = [SELECT Id FROM GroupMember WHERE Id IN :groupMemberIds];

        if (!membersToDelete.isEmpty()) {
            delete membersToDelete;
        }
    }

}