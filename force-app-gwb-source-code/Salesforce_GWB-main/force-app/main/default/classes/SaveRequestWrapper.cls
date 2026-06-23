public with sharing class SaveRequestWrapper {
    @AuraEnabled public List<InitiativeSectionWrapper> sections;

    public SaveRequestWrapper() {
        sections = new List<InitiativeSectionWrapper>();
    }
}