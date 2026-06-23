public with sharing class InitiativeSectionWrapper {
    @AuraEnabled public String key;
    @AuraEnabled public String initiativeDateOption;
    @AuraEnabled public Integer year;
    @AuraEnabled public String month;
    @AuraEnabled public Boolean editable;
    @AuraEnabled public Integer totalAdjustments;
    @AuraEnabled public Integer initiativePositionAdjustment;
    @AuraEnabled public Id parentInitiativeId;
    @AuraEnabled public Boolean hasParentInitiative;
    @AuraEnabled public Boolean isContainmentDriver;
    @AuraEnabled public Boolean addFunctionsAllowed;
    @AuraEnabled public List<GwbFunctionWrapper> gwbFunctions;

    public InitiativeSectionWrapper() {
        editable = true;
        totalAdjustments = 0;
        initiativePositionAdjustment = 0;
        hasParentInitiative = false;
        isContainmentDriver = false;
        addFunctionsAllowed = true;
        gwbFunctions = new List<GwbFunctionWrapper>();
    }
}