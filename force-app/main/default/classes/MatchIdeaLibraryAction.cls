public with sharing class MatchIdeaLibraryAction {

    public class IdeaMatch {
        @InvocableVariable(label='Idea Library ID')
        public Id ideaLibraryId;
        @InvocableVariable(label='Idea Name')
        public String ideaName;
        @InvocableVariable(label='Idea Category')
        public String ideaCategory;
        @InvocableVariable(label='FTE Min')
        public Decimal fteMin;
        @InvocableVariable(label='FTE Max')
        public Decimal fteMax;
        @InvocableVariable(label='Effort')
        public String effort;
        @InvocableVariable(label='Requires Safety Review')
        public Boolean requiresSafetyReview;
        @InvocableVariable(label='Requires Quality Review')
        public Boolean requiresQualityReview;
        @InvocableVariable(label='Requires Finance Approval')
        public Boolean requiresFinanceApproval;
        @InvocableVariable(label='Description')
        public String description;
        @InvocableVariable(label='Preconditions')
        public String preconditions;
    }

    public class MatchRequest {
        @InvocableVariable(label='Signal Type' required=true)
        public String signalType;
        @InvocableVariable(label='Max Results')
        public Integer maxResults;
    }

    public class MatchResponse {
        @InvocableVariable(label='Matched Ideas JSON')
        public String matchedIdeasJson;
        @InvocableVariable(label='Top Idea Name')
        public String topIdeaName;
        @InvocableVariable(label='Top Idea ID')
        public Id topIdeaId;
    }

    @InvocableMethod(label='Match Idea Library' description='Returns top library ideas matching the signal type')
    public static List<MatchResponse> matchIdeas(List<MatchRequest> requests) {
        List<MatchResponse> responses = new List<MatchResponse>();
        for (MatchRequest req : requests) {
            responses.add(doMatch(req));
        }
        return responses;
    }

    private static MatchResponse doMatch(MatchRequest req) {
        MatchResponse resp = new MatchResponse();
        Integer maxR = (req.maxResults != null && req.maxResults > 0) ? req.maxResults : 5;

        List<GWB_Idea_Library__c> ideas = [
            SELECT Id, Name, Idea_Category__c, Applicable_Signal_Types__c,
                   Typical_FTE_Min__c, Typical_FTE_Max__c, Typical_Effort__c,
                   Requires_Safety_Review__c, Requires_Quality_Review__c,
                   Requires_Finance_Approval__c, Description__c, Preconditions__c
            FROM GWB_Idea_Library__c
            WHERE Applicable_Signal_Types__c INCLUDES (:req.signalType)
            ORDER BY Typical_FTE_Max__c DESC NULLS LAST
            LIMIT 10
        ];

        List<IdeaMatch> matches = new List<IdeaMatch>();
        for (GWB_Idea_Library__c lib : ideas) {
            if (matches.size() >= maxR) break;
            IdeaMatch m = new IdeaMatch();
            m.ideaLibraryId          = lib.Id;
            m.ideaName               = lib.Name;
            m.ideaCategory           = lib.Idea_Category__c;
            m.fteMin                 = lib.Typical_FTE_Min__c;
            m.fteMax                 = lib.Typical_FTE_Max__c;
            m.effort                 = lib.Typical_Effort__c;
            m.requiresSafetyReview   = lib.Requires_Safety_Review__c;
            m.requiresQualityReview  = lib.Requires_Quality_Review__c;
            m.requiresFinanceApproval = lib.Requires_Finance_Approval__c;
            m.description            = lib.Description__c;
            m.preconditions          = lib.Preconditions__c;
            matches.add(m);
        }

        resp.matchedIdeasJson = JSON.serialize(matches);
        if (!matches.isEmpty()) {
            resp.topIdeaName = matches[0].ideaName;
            resp.topIdeaId   = matches[0].ideaLibraryId;
        }
        return resp;
    }
}
