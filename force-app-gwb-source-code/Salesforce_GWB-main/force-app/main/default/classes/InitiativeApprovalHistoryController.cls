public with sharing class InitiativeApprovalHistoryController {

    public class ApprovalHistoryRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String stepName { get; set; }
        @AuraEnabled public Datetime actionDate { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String comments { get; set; }
        @AuraEnabled public String assignedTo { get; set; }
        @AuraEnabled public Id assignedToId { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<ApprovalHistoryRow> getApprovalHistory(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        List<ApprovalHistoryRow> rows = new List<ApprovalHistoryRow>();

        List<ProcessInstance> instances = [
            SELECT Id,
                   (
                       SELECT Id, StepStatus, Comments, CreatedDate,
                              ActorId, OriginalActorId,
                              Actor.Name, OriginalActor.Name, ProcessNode.Name
                       FROM StepsAndWorkitems
                       ORDER BY CreatedDate DESC
                   )
            FROM ProcessInstance
            WHERE TargetObjectId = :recordId
            ORDER BY CreatedDate DESC
        ];

        for (ProcessInstance instanceRecord : instances) {
            for (ProcessInstanceHistory historyRow : instanceRecord.StepsAndWorkitems) {
                ApprovalHistoryRow row = new ApprovalHistoryRow();
                row.id = historyRow.Id;
                row.stepName = historyRow.ProcessNode != null ? historyRow.ProcessNode.Name : 'Approval Step';
                row.actionDate = historyRow.CreatedDate;
                row.status = String.isBlank(historyRow.StepStatus) ? 'Pending' : historyRow.StepStatus;
                row.comments = historyRow.Comments;
                row.assignedTo = historyRow.Actor != null
                    ? historyRow.Actor.Name
                    : (historyRow.OriginalActor != null ? historyRow.OriginalActor.Name : '');
                row.assignedToId = historyRow.ActorId != null
                    ? historyRow.ActorId
                    : historyRow.OriginalActorId;
                rows.add(row);
            }
        }

        return rows;
    }
}