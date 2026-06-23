public with sharing class InitiativeDetailController {
    @AuraEnabled(cacheable=true)
    public static List<InitiativeSectionWrapper> getForecastData(Id initiativeId) {
        return InitiativeDetailService.getForecastData(initiativeId);
    }

    @AuraEnabled(cacheable=true)
    public static List<InitiativeSectionWrapper> getActualData(Id initiativeId) {
        return InitiativeDetailService.getActualData(initiativeId);
    }

    @AuraEnabled(cacheable=true)
    public static List<GwbFunctionWrapper> getAvailablePlantFunctions(Id initiativeId) {
        return InitiativeDetailService.getAvailablePlantFunctions(initiativeId);
    }

    @AuraEnabled(cacheable=true)
    public static List<OperationWrapper> getAvailableOperations(Id initiativeId, Id plantFunctionId) {
        return InitiativeDetailService.getAvailableOperations(initiativeId, plantFunctionId);
    }

    @AuraEnabled
    public static List<InitiativeSectionWrapper> saveForecastData(Id initiativeId, String wrapperJson) {
        return InitiativeDetailService.saveForecastData(initiativeId, wrapperJson);
    }

    @AuraEnabled
    public static List<InitiativeSectionWrapper> saveActualData(Id initiativeId, String wrapperJson) {
        return InitiativeDetailService.saveActualData(initiativeId, wrapperJson);
    }
}