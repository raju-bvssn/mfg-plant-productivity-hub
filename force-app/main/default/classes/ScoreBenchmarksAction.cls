public with sharing class ScoreBenchmarksAction {

    public class ScoreRequest {
        @InvocableVariable(label='Matched Ideas JSON' required=true)
        public String matchedIdeasJson;
        @InvocableVariable(label='Shop Type')
        public String shopType;
        @InvocableVariable(label='Production Context')
        public String productionContext;
    }

    public class ScoredIdea {
        @InvocableVariable(label='Idea Library ID')
        public Id ideaLibraryId;
        @InvocableVariable(label='Idea Name')
        public String ideaName;
        @InvocableVariable(label='Confidence Score')
        public Integer confidenceScore;
        @InvocableVariable(label='Benchmark Evidence')
        public String benchmarkEvidence;
        @InvocableVariable(label='FTE Min')
        public Decimal fteMin;
        @InvocableVariable(label='FTE Max')
        public Decimal fteMax;
        @InvocableVariable(label='Effort')
        public String effort;
    }

    public class ScoreResponse {
        @InvocableVariable(label='Scored Ideas JSON')
        public String scoredIdeasJson;
        @InvocableVariable(label='Top Idea ID')
        public Id topIdeaId;
        @InvocableVariable(label='Top Idea Name')
        public String topIdeaName;
        @InvocableVariable(label='Top Confidence Score')
        public Integer topConfidenceScore;
        @InvocableVariable(label='Top Benchmark Evidence')
        public String topBenchmarkEvidence;
    }

    @InvocableMethod(label='Score Benchmarks' description='Scores matched ideas using cross-plant benchmark data')
    public static List<ScoreResponse> score(List<ScoreRequest> requests) {
        List<ScoreResponse> responses = new List<ScoreResponse>();
        for (ScoreRequest req : requests) {
            responses.add(doScore(req));
        }
        return responses;
    }

    private static ScoreResponse doScore(ScoreRequest req) {
        ScoreResponse resp = new ScoreResponse();

        List<Object> rawIdeas = (List<Object>) JSON.deserializeUntyped(req.matchedIdeasJson);
        List<Id> ideaIds = new List<Id>();
        Map<Id, Map<String, Object>> ideaMap = new Map<Id, Map<String, Object>>();

        for (Object raw : rawIdeas) {
            Map<String, Object> m = (Map<String, Object>) raw;
            Id libId = (Id) m.get('ideaLibraryId');
            ideaIds.add(libId);
            ideaMap.put(libId, m);
        }

        List<GWB_Plant_Benchmark__c> benchmarks = [
            SELECT Id, Idea_Library__c, Shop_Type__c, Achieved_FTE__c,
                   Quarter__c, Production_Context__c, Notes__c,
                   Plant__r.Name
            FROM GWB_Plant_Benchmark__c
            WHERE Idea_Library__c IN :ideaIds
        ];

        Map<Id, List<GWB_Plant_Benchmark__c>> benchByIdea = new Map<Id, List<GWB_Plant_Benchmark__c>>();
        for (GWB_Plant_Benchmark__c b : benchmarks) {
            if (!benchByIdea.containsKey(b.Idea_Library__c))
                benchByIdea.put(b.Idea_Library__c, new List<GWB_Plant_Benchmark__c>());
            benchByIdea.get(b.Idea_Library__c).add(b);
        }

        List<ScoredIdea> scored = new List<ScoredIdea>();
        for (Id libId : ideaIds) {
            Map<String, Object> idea = ideaMap.get(libId);
            ScoredIdea si = new ScoredIdea();
            si.ideaLibraryId = libId;
            si.ideaName      = (String) idea.get('ideaName');
            si.fteMin        = idea.get('fteMin') != null ? Decimal.valueOf(String.valueOf(idea.get('fteMin'))) : 0;
            si.fteMax        = idea.get('fteMax') != null ? Decimal.valueOf(String.valueOf(idea.get('fteMax'))) : 0;
            si.effort        = (String) idea.get('effort');

            Integer score = 50;
            List<String> evidenceParts = new List<String>();

            List<GWB_Plant_Benchmark__c> benches = benchByIdea.get(libId);
            if (benches != null && !benches.isEmpty()) {
                score += 20;
                for (GWB_Plant_Benchmark__c b : benches) {
                    if (req.shopType != null && b.Shop_Type__c == req.shopType) score += 10;
                    evidenceParts.add(b.Plant__r.Name + ': ' + b.Achieved_FTE__c + ' FTE (' + b.Quarter__c + ')');
                }
            }
            if (si.fteMax != null && si.fteMax >= 1.0) score += 5;
            if (si.effort == 'Low') score += 5;
            score = Math.min(score, 99);

            si.confidenceScore  = score;
            si.benchmarkEvidence = String.join(evidenceParts, '; ');
            scored.add(si);
        }

        scored.sort(new ScoredIdeaComparator());

        resp.scoredIdeasJson = JSON.serialize(scored);
        if (!scored.isEmpty()) {
            resp.topIdeaId          = scored[0].ideaLibraryId;
            resp.topIdeaName        = scored[0].ideaName;
            resp.topConfidenceScore = scored[0].confidenceScore;
            resp.topBenchmarkEvidence = scored[0].benchmarkEvidence;
        }
        return resp;
    }

    private class ScoredIdeaComparator implements Comparator<ScoredIdea> {
        public Integer compare(ScoredIdea a, ScoredIdea b) {
            return b.confidenceScore - a.confidenceScore;
        }
    }
}
