public with sharing class CreateIdeaRecordAction {

    public class CreateIdeaRequest {
        @InvocableVariable(label='Plant Function ID')
        public Id plantFunctionId;
        @InvocableVariable(label='Idea Library ID')
        public Id ideaLibraryId;
        @InvocableVariable(label='Edge Signal ID')
        public Id edgeSignalId;
        @InvocableVariable(label='Idea Title' required=true)
        public String ideaTitle;
        @InvocableVariable(label='FTE Impact')
        public Decimal fteImpact;
        @InvocableVariable(label='Dollar Impact')
        public Decimal dollarImpact;
        @InvocableVariable(label='Confidence Score')
        public Integer confidenceScore;
        @InvocableVariable(label='Effort')
        public String effort;
        @InvocableVariable(label='Assumptions')
        public String assumptions;
        @InvocableVariable(label='Benchmark Evidence')
        public String benchmarkEvidence;
        @InvocableVariable(label='Required Validations')
        public String requiredValidations;
        @InvocableVariable(label='Risk Notes')
        public String riskNotes;
    }

    public class CreateIdeaResponse {
        @InvocableVariable(label='Idea Record ID')
        public Id ideaId;
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(label='Create Productivity Idea' description='Creates a GWB_Productivity_Idea__c record with status Pending Approval')
    public static List<CreateIdeaResponse> createIdea(List<CreateIdeaRequest> requests) {
        List<CreateIdeaResponse> responses = new List<CreateIdeaResponse>();
        for (CreateIdeaRequest req : requests) {
            responses.add(doCreate(req));
        }
        return responses;
    }

    private static CreateIdeaResponse doCreate(CreateIdeaRequest req) {
        CreateIdeaResponse resp = new CreateIdeaResponse();
        try {
            GWB_Productivity_Idea__c idea = new GWB_Productivity_Idea__c();
            idea.Name                  = req.ideaTitle;
            idea.Plant_Function__c     = req.plantFunctionId;
            idea.Idea_Library__c       = req.ideaLibraryId;
            idea.Edge_Signal__c        = req.edgeSignalId;
            idea.Status__c             = 'Pending Approval';
            idea.Idea_Type__c          = 'Permanent';
            idea.AI_Generated__c       = true;
            idea.FTE_Impact__c         = req.fteImpact;
            idea.Dollar_Impact__c      = req.dollarImpact;
            idea.Confidence_Score__c   = req.confidenceScore;
            idea.Effort__c             = req.effort;
            idea.Assumptions__c        = req.assumptions;
            idea.Benchmark_Evidence__c = req.benchmarkEvidence;
            idea.Required_Validations__c = req.requiredValidations;
            idea.Risk_Notes__c         = req.riskNotes;

            insert idea;
            resp.ideaId  = idea.Id;
            resp.success = true;
        } catch (Exception e) {
            resp.success      = false;
            resp.errorMessage = e.getMessage();
        }
        return resp;
    }
}
