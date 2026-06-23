public with sharing class OperationWrapper {
    @AuraEnabled public Id id;
    @AuraEnabled public Id authorizedDatabaseId;
    @AuraEnabled public Id operationId;
    @AuraEnabled public String operationIdentifier;
    @AuraEnabled public String area;
    @AuraEnabled public String equipment;
    @AuraEnabled public String comment;
    @AuraEnabled public Integer crew1;
    @AuraEnabled public Integer crew2;
    @AuraEnabled public Integer crew3;
    @AuraEnabled public Integer total;

    public OperationWrapper() {
        crew1 = 0;
        crew2 = 0;
        crew3 = 0;
        total = 0;
    }
}