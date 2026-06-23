public with sharing class GwbFunctionWrapper {
    @AuraEnabled public Id id;
    @AuraEnabled public Id workbookId;
    @AuraEnabled public Id plantFunctionId;
    @AuraEnabled public String plantFunctionName;
    @AuraEnabled public String programName;
    @AuraEnabled public String programCode;
    @AuraEnabled public String functionLevel;
    @AuraEnabled public String functionArea;
    @AuraEnabled public String line;
    @AuraEnabled public String module;
    @AuraEnabled public Integer crewEditableCount;
    @AuraEnabled public Integer crew1;
    @AuraEnabled public Integer crew2;
    @AuraEnabled public Integer crew3;
    @AuraEnabled public Integer displayCrew1;
    @AuraEnabled public Integer displayCrew2;
    @AuraEnabled public Integer displayCrew3;
    @AuraEnabled public Integer actualCrew1;
    @AuraEnabled public Integer actualCrew2;
    @AuraEnabled public Integer actualCrew3;
    @AuraEnabled public Integer actualTotal;
    @AuraEnabled public Integer total;
    @AuraEnabled public Boolean editable;
    @AuraEnabled public Boolean hasActiveOperations;
    @AuraEnabled public List<OperationWrapper> operations;

    public GwbFunctionWrapper() {
        crewEditableCount = 1;
        crew1 = 0;
        crew2 = 0;
        crew3 = 0;
        displayCrew1 = null;
        displayCrew2 = null;
        displayCrew3 = null;
        actualCrew1 = 0;
        actualCrew2 = 0;
        actualCrew3 = 0;
        actualTotal = 0;
        total = 0;
        editable = true;
        hasActiveOperations = false;
        operations = new List<OperationWrapper>();
    }
}