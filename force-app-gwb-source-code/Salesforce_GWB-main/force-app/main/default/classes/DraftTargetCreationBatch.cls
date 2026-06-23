public with sharing class DraftTargetCreationBatch implements Database.Batchable<SObject>, Database.Stateful {
    private final Set<Id> plantSectorIds;
    private final String versionValue;
    private final Id initiatedByUserId;

    private Integer successCount = 0;
    private Integer failureCount = 0;
    private List<String> failureMessages = new List<String>();
    private List<String> successMessages = new List<String>();

    public DraftTargetCreationBatch(List<Id> plantSectorIds, String versionValue, Id initiatedByUserId) {
        this.plantSectorIds = plantSectorIds == null ? new Set<Id>() : new Set<Id>(plantSectorIds);
        this.versionValue = versionValue;
        this.initiatedByUserId = initiatedByUserId;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Plant__c, Plant__r.Name, Plant__r.Vehicle_Brand__c, Plant__r.Auth_Sector__c,
                   Plant_Program__c, Program_Code__c, Functional_Area__c,
                   Sector__c, Auth_Sector__c
            FROM Plant_Sector__c
            WHERE Id IN :plantSectorIds
            ORDER BY Plant__r.Name, Sector__c
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Plant_Sector__c> plantSectors = new List<Plant_Sector__c>();
        for (SObject record : scope) {
            plantSectors.add((Plant_Sector__c) record);
        }

        DraftTargetCreationService.ProcessingResult result =
            DraftTargetCreationService.processPlantSectors(plantSectors, versionValue, null, null);

        successCount += result.successCount;
        failureCount += result.failureCount;
        for (String message : result.successMessages) {
            if (successMessages.size() >= 25) {
                break;
            }
            successMessages.add(message);
        }
        for (String message : result.failureMessages) {
            if (failureMessages.size() >= 25) {
                break;
            }
            failureMessages.add(message);
        }

        System.debug(
            LoggingLevel.INFO,
            'DraftTargetCreationBatch | Scope complete | SuccessCount=' + result.successCount +
            ' | FailureCount=' + result.failureCount +
            ' | SuccessSamples=' + result.successMessages.size() +
            ' | FailureSamples=' + result.failureMessages.size()
        );
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
        email.setSubject('Draft target background processing completed');

        List<String> bodyLines = new List<String>{
            'Hello ' + users[0].Name + ',',
            '',
            'Your draft target background job has completed.',
            'Successfully processed: ' + String.valueOf(successCount),
            'Failed: ' + String.valueOf(failureCount)
        };

        if (!successMessages.isEmpty()) {
            bodyLines.add('');
            bodyLines.add('Sample success details:');
            bodyLines.addAll(successMessages);
        }

        if (!failureMessages.isEmpty()) {
            bodyLines.add('');
            bodyLines.add('Sample failure details:');
            bodyLines.addAll(failureMessages);
        }

        email.setPlainTextBody(String.join(bodyLines, '\n'));
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

        System.debug(
            LoggingLevel.INFO,
            'DraftTargetCreationBatch | Finish summary | SuccessCount=' + successCount +
            ' | FailureCount=' + failureCount +
            ' | SuccessSamples=' + successMessages.size() +
            ' | FailureSamples=' + failureMessages.size()
        );
    }
}