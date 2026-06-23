public with sharing class DraftTargetCloneBatch implements Database.Batchable<SObject>, Database.Stateful {
    private final Set<Id> targetIds;
    private final String versionValue;
    private final Id initiatedByUserId;

    private Integer successCount = 0;
    private Integer failureCount = 0;
    private List<String> failureMessages = new List<String>();

    public DraftTargetCloneBatch(List<Id> targetIds, String versionValue, Id initiatedByUserId) {
        this.targetIds = targetIds == null ? new Set<Id>() : new Set<Id>(targetIds);
        this.versionValue = versionValue;
        this.initiatedByUserId = initiatedByUserId;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM GWB_Year__c
            WHERE Id IN :targetIds
            ORDER BY CreatedDate DESC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Id> scopeIds = new List<Id>();
        for (SObject record : scope) {
            scopeIds.add((Id)record.get('Id'));
        }

        try {
            DraftTargetController.CloneDraftTargetResult result =
                DraftTargetController.cloneDraftTargets(scopeIds, versionValue);
            successCount += result != null && result.submittedCount != null ? result.submittedCount : scopeIds.size();
        } catch (Exception e) {
            failureCount += scopeIds.size();
            if (failureMessages.size() < 25) {
                failureMessages.add(e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        sendCompletionEmail();
    }

    private void sendCompletionEmail() {
        if (initiatedByUserId == null) {
            return;
        }

        List<User> users = [
            SELECT Id, Name, Email
            FROM User
            WHERE Id = :initiatedByUserId
            LIMIT 1
        ];
        if (users.isEmpty() || String.isBlank(users[0].Email)) {
            return;
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ users[0].Email });
        email.setSubject('Draft target clone completed');

        List<String> bodyLines = new List<String>{
            'Hello ' + users[0].Name + ',',
            '',
            'Your draft target clone job has completed.',
            'Successfully processed: ' + String.valueOf(successCount),
            'Failed: ' + String.valueOf(failureCount)
        };

        if (!failureMessages.isEmpty()) {
            bodyLines.add('');
            bodyLines.add('Sample failure details:');
            bodyLines.addAll(failureMessages);
        }

        email.setPlainTextBody(String.join(bodyLines, '\n'));
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
}