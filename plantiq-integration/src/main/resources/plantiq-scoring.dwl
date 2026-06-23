%dw 2.0
output application/java

/*
  Score each matched Idea Library record against available benchmarks.

  Scoring formula (mirrors ScoreBenchmarksAction.cls):
    score = (benchmarkCount * avgAchievedFTE) / constraintWeight

  constraintWeight: +1 for each required review flag (safety/quality/finance)
  benchmarkEvidence: human-readable string listing plant/quarter evidence
*/

var ideas      = vars.matchedIdeas
var benchmarks = vars.benchmarks
var ctx        = vars.plantContext

fun benchmarksForIdea(ideaId: String) =
    benchmarks filter ($.Idea_Library__c == ideaId)

fun constraintWeight(idea) =
    1
    + (if (idea.Requires_Safety_Review__c  default false) 1 else 0)
    + (if (idea.Requires_Quality_Review__c default false) 1 else 0)
    + (if (idea.Requires_Finance_Approval__c default false) 1 else 0)

fun avgFTE(bs: Array) =
    if (sizeOf(bs) == 0) 0
    else (bs reduce ((b, acc = 0.0) -> acc + (b.Achieved_FTE__c default 0.0))) / sizeOf(bs)

fun evidenceText(bs: Array) =
    if (sizeOf(bs) == 0) "No cross-plant benchmarks available"
    else bs map ("Plant " ++ ($.`Plant__r.Plant_Code__c` default "?") ++ " achieved " ++
                 (($.Achieved_FTE__c default 0) as String) ++ " FTE in " ++
                 ($.Quarter__c default "?")) joinBy "; "

---
ideas
    map (idea) -> do {
        var bs    = benchmarksForIdea(idea.Id)
        var score = (sizeOf(bs) * avgFTE(bs)) / constraintWeight(idea)
        ---
        {
            ideaId:           idea.Id,
            ideaName:         idea.Name,
            ideaCategory:     idea.Idea_Category__c,
            typicalFTEMin:    idea.Typical_FTE_Min__c default 0,
            typicalFTEMax:    idea.Typical_FTE_Max__c default 0,
            effort:           idea.Typical_Effort__c default "Medium",
            score:            score,
            benchmarkCount:   sizeOf(bs),
            benchmarkEvidence: evidenceText(bs)
        }
    }
    orderBy (item) -> -(item.score)
