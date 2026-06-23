import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasPlantAdminPermission from '@salesforce/customPermission/Plant_Admin';
import hasGwbSystemAdminPermission from '@salesforce/customPermission/GWB_System_Admin';
import hasIndustrialEngineerPermission from '@salesforce/customPermission/Industrial_Engineer';
import getBudgetContext from '@salesforce/apex/GwbBudgetWorkbenchController.getBudgetContext';
import getBudgetDetail from '@salesforce/apex/GwbBudgetWorkbenchController.getBudgetDetail';
import saveBudgetRows from '@salesforce/apex/GwbBudgetWorkbenchController.saveBudgetRows';
import updateBudgetState from '@salesforce/apex/GwbBudgetWorkbenchController.updateBudgetState';
import getBudgetStatusOptions from '@salesforce/apex/GwbBudgetWorkbenchController.getBudgetStatusOptions';
import saveBudgetComment from '@salesforce/apex/GwbBudgetWorkbenchController.saveBudgetComment';
import cloneDraftTargets from '@salesforce/apex/DraftTargetController.cloneDraftTargets';
import getMScheduleOptions from '@salesforce/apex/DraftTargetController.getMScheduleOptions';

const MONTH_COLUMNS = [
    { key: 'prevDec', label: "Dec'25", editable: false },
    { key: 'jan', label: 'Jan', editable: true },
    { key: 'feb', label: 'Feb', editable: true },
    { key: 'mar', label: 'Mar', editable: true },
    { key: 'apr', label: 'Apr', editable: true },
    { key: 'may', label: 'May', editable: true },
    { key: 'jun', label: 'Jun', editable: true },
    { key: 'jul', label: 'Jul', editable: true },
    { key: 'aug', label: 'Aug', editable: true },
    { key: 'sep', label: 'Sep', editable: true },
    { key: 'oct', label: 'Oct', editable: true },
    { key: 'nov', label: 'Nov', editable: true },
    { key: 'dec', label: 'Dec', editable: true }
];

const OPEN_SECTIONS = ['nonDriver', 'driver', 'hours', 'summary'];
const SECTION_ORDER = ['nonDriver', 'driver', 'hours', 'summary', 'comparison'];
const SECTION_LABELS = {
    nonDriver: 'Non-Driver Input Information',
    driver: 'Base Positions',
    hours: 'Hour Calculations',
    summary: 'Summary',
    comparison: 'Summary with Comparison'
};
const ZERO_MONTH_VALUES = {
    prevDec: 0,
    jan: 0,
    feb: 0,
    mar: 0,
    apr: 0,
    may: 0,
    jun: 0,
    jul: 0,
    aug: 0,
    sep: 0,
    oct: 0,
    nov: 0,
    dec: 0
};
const EMPTY_MONTH_VALUES = {
    prevDec: null,
    jan: null,
    feb: null,
    mar: null,
    apr: null,
    may: null,
    jun: null,
    jul: null,
    aug: null,
    sep: null,
    oct: null,
    nov: null,
    dec: null
};
const FILL_FORWARD_ROW_KEYS = new Set([
    'crews',
    'shifts',
    'netJph',
    'paidHoursPerCrew',
    'absenteeism-ots',
    'absenteeism-skilled',
    'absenteeism-salaried',
    'nsot-ots',
    'nsot-skilled',
    'nsot-salaried'
]);
const ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS = ['astadj-ots', 'astadj-skilled', 'astadj-salaried'];
const ADDITIONAL_ST_JUSTIFICATION_LABEL = 'Additional ST Adjustment Reason';
const EXCLUDED_STATUS_UPDATE_VALUES = new Set(['Draft', 'Published', 'Locked']);
const CUMULATIVE_AVERAGE_HC_DRIVERS = new Set([
    'Productivity',
    'MBC',
    'LMS',
    'Op Plan',
    'Vacation Coverage',
    'Content Changes',
    'Sourcing',
    'Other / Excess'
]);
const UI_TO_SHARED_CLASSIFICATION = {
    OTS: 'OTS',
    Skilled: 'Skilled',
    Salaried: 'Salaried'
};
const SHARED_ROW_META = {
    crews: { section: 'Scheduled_Volume', parameter: 'Crews', classification: null, objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    shifts: { section: 'Scheduled_Volume', parameter: 'Shifts', classification: null, objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    netJph: { section: 'Scheduled_Volume', parameter: 'Net/Net JPH', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true },
    calcVolume: { section: 'Scheduled_Volume', parameter: 'Calculated Volume incl. SOT', classification: null, objectApiName: 'GWB_Month__c', valueType: 'number', persist: false },
    scheduledVolume: { section: 'Scheduled_Volume', parameter: 'Scheduled Volume', classification: null, objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    volumeVariance: { section: 'Scheduled_Volume', parameter: 'Volume Variance', classification: null, objectApiName: 'GWB_Month__c', valueType: 'number', persist: false },
    paidHoursPerCrew: { section: 'Scheduled_Volume', parameter: 'Paid Hours Per CREW', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true },
    availableDays: { section: 'Scheduled_Volume', parameter: 'Available Working Days/Month', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true },
    productionDays: { section: 'Scheduled_Volume', parameter: 'Production Working Days/Month', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true },
    eqSotDays: { section: 'Scheduled_Volume', parameter: 'EQ SOT Days', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true },
    'absenteeism-ots': { section: 'Manpower', parameter: 'Absenteeism %', classification: 'OTS', objectApiName: 'GWB_Month__c', valueType: 'percent', persist: true },
    'absenteeism-skilled': { section: 'Manpower', parameter: 'Absenteeism %', classification: 'Skilled', objectApiName: 'GWB_Month__c', valueType: 'percent', persist: true },
    'absenteeism-salaried': { section: 'Manpower', parameter: 'Absenteeism %', classification: 'Salaried', objectApiName: 'GWB_Month__c', valueType: 'percent', persist: true },
    'nsot-ots': { section: 'Manpower', parameter: 'NSOT %', classification: 'OTS', objectApiName: 'GWB_Month__c', valueType: 'percent', persist: true },
    'nsot-skilled': { section: 'Manpower', parameter: 'NSOT %', classification: 'Skilled', objectApiName: 'GWB_Month__c', valueType: 'percent', persist: true },
    'nsot-salaried': { section: 'Manpower', parameter: 'NSOT %', classification: 'Salaried', objectApiName: 'GWB_Month__c', valueType: 'percent', persist: true },
    'base-ots': { section: 'Manpower', parameter: 'Base Headcount', classification: 'OTS', objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    'base-skilled': { section: 'Manpower', parameter: 'Base Headcount', classification: 'Skilled', objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    'base-salaried': { section: 'Manpower', parameter: 'Base Headcount', classification: 'Salaried', objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    'approved-ots': { section: 'Manpower', parameter: 'Approved Target', classification: 'OTS', objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    'approved-skilled': { section: 'Manpower', parameter: 'Approved Target', classification: 'Skilled', objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    'approved-salaried': { section: 'Manpower', parameter: 'Approved Target', classification: 'Salaried', objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    'astadj-ots': { section: 'Manpower', parameter: 'Additional Straight Time Hours Adjustment', classification: 'OTS', objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    'astadj-skilled': { section: 'Manpower', parameter: 'Additional Straight Time Hours Adjustment', classification: 'Skilled', objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    'astadj-salaried': { section: 'Manpower', parameter: 'Additional Straight Time Hours Adjustment', classification: 'Salaried', objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    gpsFinalAssemblyLineJph: { section: 'Scheduled_Volume', parameter: 'Final Assembly Line JPH', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true },
    gpsDailyOpPlanVolume: { section: 'Scheduled_Volume', parameter: 'Daily Op Plan Volume', classification: null, objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    gpsSotDaysWeekends: { section: 'Scheduled_Volume', parameter: 'SOT days (Weekends)', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true },
    gpsTotalSotDays: { section: 'Scheduled_Volume', parameter: 'Total SOT Days', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true },
    stampingEquivalentUnitsVolume: { section: 'Scheduled_Volume', parameter: 'Equivalent Units Volume', classification: null, objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    stampingDailyOpPlanVolume: { section: 'Scheduled_Volume', parameter: 'Daily Op Plan Volume', classification: null, objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    stampingHarbourStrokesHpu: { section: 'Scheduled_Volume', parameter: 'HARBOUR STROKES HPU', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true },
    stampingScheduledVolumePieces: { section: 'Scheduled_Volume', parameter: 'Scheduled Volume Pieces', classification: null, objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    stampingScheduledVolumeStrokes: { section: 'Scheduled_Volume', parameter: 'Scheduled Volume Strokes', classification: null, objectApiName: 'GWB_Month__c', valueType: 'number', persist: true },
    stampingEquivalentSotPct: { section: 'Scheduled_Volume', parameter: 'Equivalent SOT %', classification: null, objectApiName: 'GWB_Month__c', valueType: 'percent', persist: true },
    stampingSotPercentWeekendDays: { section: 'Scheduled_Volume', parameter: 'SOT percent from weekend days', classification: null, objectApiName: 'GWB_Month__c', valueType: 'percent', persist: true },
    stampingSotFromLineTime: { section: 'Scheduled_Volume', parameter: 'SOT from line time', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true },
    stampingSotEquivalentDaysTotal: { section: 'Scheduled_Volume', parameter: 'SOT equivalent days total', classification: null, objectApiName: 'GWB_Month__c', valueType: 'decimal', persist: true }
};
const DRIVER_ROW_META = {
    'prod-ots': { driver: 'Productivity', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'prod-skilled': { driver: 'Productivity', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'prod-salaried': { driver: 'Productivity', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true },
    'mbc-ots': { driver: 'ARC', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'mbc-skilled': { driver: 'ARC', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'mbc-salaried': { driver: 'ARC', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true },
    'lms-ots': { driver: 'LMS', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'lms-skilled': { driver: 'LMS', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'lms-salaried': { driver: 'LMS', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true },
    'opplan-ots': { driver: 'Op Plan', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'opplan-skilled': { driver: 'Op Plan', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'opplan-salaried': { driver: 'Op Plan', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true },
    'vac-ots': { driver: 'Vacation Replacement', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'vac-skilled': { driver: 'Vacation Replacement', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'vac-salaried': { driver: 'Vacation Replacement', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true },
    'content-ots': { driver: 'Content', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'content-skilled': { driver: 'Content', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'content-salaried': { driver: 'Content', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true },
    'sourcing-ots': { driver: 'Sourcing', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'sourcing-skilled': { driver: 'Sourcing', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'sourcing-salaried': { driver: 'Sourcing', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true },
    'mfgopt-ots': { driver: 'Mfg Opt', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'mfgopt-skilled': { driver: 'Mfg Opt', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'mfgopt-salaried': { driver: 'Mfg Opt', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true },
    'launch-ots': { driver: 'Launch', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'launch-skilled': { driver: 'Launch', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'launch-salaried': { driver: 'Launch', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true },
    'containment-ots': { driver: 'Containment', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'containment-skilled': { driver: 'Containment', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'containment-salaried': { driver: 'Containment', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true },
    'others-ots': { driver: 'Other/Excess', classification: 'OTS', objectApiName: 'GWB_Month__c', persist: true },
    'others-skilled': { driver: 'Other/Excess', classification: 'Skilled', objectApiName: 'GWB_Month__c', persist: true },
    'others-salaried': { driver: 'Other/Excess', classification: 'Salaried', objectApiName: 'GWB_Month__c', persist: true }
};
const FORMULA_TEXT_BY_KEY = {
    calcVolume: 'Calculated Volume = Net/Net JPH x Paid Hours Per CREW x (Production Working Days + EQ SOT Days) x Number of Shifts',
    scheduledVolume: 'Scheduled Volume is the monthly target volume input copied from the target draft / M-Schedule source and remains editable.',
    volumeVariance: 'Scheduled Volume minus Calculated Volume = Scheduled Volume - Calculated Volume incl. SOT days',
    gpsTotalSotDays: 'Total SOT Days = SOT days (Weekends) + EQ SOT Days.',
    stampingEquivalentSotPct: 'Input value: Equivalent SOT %.',
    stampingSotPercentWeekendDays: 'Input value: SOT percent from weekend days.',
    stampingSotFromLineTime: 'Input value: SOT from line time.',
    stampingSotEquivalentDaysTotal: 'SOT equivalent days total = Production Working Days / Month x Equivalent SOT % (Press only).',
    'absenteeism-ots': 'Input value: monthly absenteeism % entered for OTS.',
    'absenteeism-skilled': 'Input value: monthly absenteeism % entered for Skilled.',
    'absenteeism-salaried': 'Input value: monthly absenteeism % entered for Salaried.',
    absenteeism: 'Input value: monthly absenteeism % entered by classification. Total row shows the manpower-weighted average.',
    'nsot-ots': 'Input value: NSOT % where NSOT % = NSOT / (ST + SOT) for OTS.',
    'nsot-skilled': 'Input value: NSOT % where NSOT % = NSOT / (ST + SOT) for Skilled.',
    'nsot-salaried': 'Input value: NSOT % where NSOT % = NSOT / (ST + SOT) for Salaried.',
    nsot: 'Input value: NSOT % where NSOT % = NSOT / (ST + SOT), entered by classification. Total row is derived from total NSOT, ST, and SOT hours.',
    'total-ots': 'Total Manpower formula: Previous December shows Base Headcount Prev Dec + Approved Target Prev Dec for OTS. Jan = Previous December total for OTS + OTS adjustment row values for Jan. Feb-Dec = prior month Total Manpower for OTS + OTS adjustment row values for the same month, excluding Base Headcount and Approved Target monthly values.',
    'total-skilled': 'Total Manpower formula: Previous December shows Base Headcount Prev Dec + Approved Target Prev Dec for Skilled. Jan = Previous December total for Skilled + Skilled adjustment row values for Jan. Feb-Dec = prior month Total Manpower for Skilled + Skilled adjustment row values for the same month, excluding Base Headcount and Approved Target monthly values.',
    'total-salaried': 'Total Manpower formula: Previous December shows Base Headcount Prev Dec + Approved Target Prev Dec for Salaried. Jan = Previous December total for Salaried + Salaried adjustment row values for Jan. Feb-Dec = prior month Total Manpower for Salaried + Salaried adjustment row values for the same month, excluding Base Headcount and Approved Target monthly values.',
    combinedAbsence: 'Summer VRO % = YTD Vacation Coverage / Total Manpower. Row value shown = Absenteeism % + Summer VRO %.',
    scheduledOvertime: 'Scheduled Overtime Hours = Total Manpower x (1 - (Absenteeism % + Summer VRO %)) x Paid Hours Per CREW x EQ SOT Days x (Shifts / Crews)',
    additionalStraightTime: "Additional ST Hours = Total Manpower x (1 - Absenteeism %) x (Shifts / Crews) x Paid Hours Per CREW x multiplier x (Available Days - Production Days). Multiplier: OTS 0.2, Skilled 0.95, Salaried 0. Total row = OTS + Skilled + Salaried for the month. Avg / Total = Jan-Dec sum.",
    additionalStraightTimeAdjustment: 'Manual positive/negative adjustment entered on top of the calculated Additional ST Hours value. This value is persisted as a classified GWB Month parameter row.',
    vacationCoverage: 'Assembly OTS Vacation Coverage is derived from the configured vacation record. Entry month adds Vacation % x total manpower before vacation for that month. Exit month subtracts that same value. Other Vacation Coverage rows remain normal inputs.',
    stHours: "ST Hours = Total Manpower x (1 - (Absenteeism % + Summer VRO %)) x Paid Hours Per CREW x Production Working Days x (Shifts / Crews) + Additional ST Hours",
    nsotHours: 'NSOT Hours by classification = (ST Hours + Scheduled Overtime Hours) x NSOT %. Total row = OTS + Skilled + Salaried for the same month.',
    totalHours: 'Total Hours = ST Hours + NSOT Hours + Scheduled Overtime Hours',
    prodPct: '% Productivity = (sum of Productivity + ARC/MBC + LMS adjustments) / previous-year total manpower',
    averageTotal: 'Average Total = average of Jan-Dec Total Manpower across all classifications.',
    stHoursTile: "ST Hours card = Jan-Dec sum of ST Hours for OTS + Skilled + Salaried.",
    nsotHoursTile: 'NSOT Hours card = Jan-Dec sum of NSOT Hours for OTS + Skilled + Salaried.',
    nsotCyPct: 'NSOT CY % = Total NSOT Hours / (Total ST Hours + Total Scheduled Overtime Hours)',
    sotCyPct: 'SOT CY % = Total Scheduled Overtime Hours / Total ST Hours',
    additionalSt: 'Additional ST Hours card = Jan-Dec sum of calculated Additional ST Hours plus adjustments across all classifications.',
    totalHoursTile: 'Total Hours card = Jan-Dec sum of Total Hours for OTS + Skilled + Salaried.',
    pyeHeadcount: 'PYE Headcount = previous December total manpower across all classifications.',
    cyeHeadcount: 'CYE Headcount = current December total manpower across all classifications.',
    cyAveHeadcount: 'CY Ave. Headcount = average of Jan-Dec total manpower across all classifications.',
    summaryOpPlan: 'YE uses the configured row YE rule (mostly Dec or sum). CY Average uses the Jan-Dec average for the same row.',
    summaryHours: 'YE is the Jan-Dec year total for each calculated hours metric. CY Average is the monthly average of that same total.',
    summaryHeadcount: 'YE / CY Average rollups come from combined driver rows and total manpower across classifications.'
};

export function getFormulaTextByKey(key) {
    return FORMULA_TEXT_BY_KEY[key] || '';
}

export function getSummaryHeadcountFormulaText(label) {
    const formulaByLabel = {
        'YE Target': 'YE Target = previous December Base Headcount plus previous December Approved Target across OTS, Skilled, and Salaried.',
        'Productivity (all in)': 'Productivity (all in) = December sum of Productivity + ARC/MBC + LMS adjustments across all classifications.',
        'Op Plan Changes': 'Op Plan Changes = December sum of Op Plan adjustments across all classifications.',
        'Vacation Coverage': 'Vacation Coverage = December sum of Vacation Coverage adjustments across all classifications.',
        'Content Changes': 'Content Changes = December sum of Content changes across all classifications.',
        Sourcing: 'Sourcing = December sum of Sourcing adjustments across all classifications.',
        Others: 'Others = December sum of Other/Excess adjustments across all classifications.',
        'Mfg Op': 'Mfg Op = December sum of Mfg Opt adjustments across all classifications.',
        'YE Total': 'YE Total = December total manpower across all classifications after all headcount adjustments.',
        'CY Ave.': 'CY Ave. = Jan-Dec average of total manpower across all classifications.'
    };

    return formulaByLabel[label] || getFormulaTextByKey('summaryHeadcount');
}

export function getTotalClassificationHelpText(row) {
    const baseFormulaKey = row.formulaKey || getBaseFormulaKey(row.key);
    if (baseFormulaKey === 'combinedAbsence') {
        return 'Total = weighted average of OTS, Skilled, and Salaried using Total Manpower for the same month as weights.';
    }
    if (baseFormulaKey === 'nsot' || baseFormulaKey === 'nsot-ots') {
        return 'Total NSOT % = Total NSOT Hours / (Total ST Hours + Total Scheduled Overtime Hours) for the same month.';
    }
    if (baseFormulaKey === 'scheduledOvertime' ||
        baseFormulaKey === 'additionalStraightTime' ||
        baseFormulaKey === 'nsotHours' ||
        baseFormulaKey === 'stHours' ||
        baseFormulaKey === 'totalHours' ||
        baseFormulaKey === 'base-ots' ||
        baseFormulaKey === 'total-ots') {
        return 'Total = OTS + Skilled + Salaried for the same month.';
    }
    return 'Total = rollup across OTS, Skilled, and Salaried for the same month.';
}

function getAllowedStatusUpdateOptions(options) {
    return (options || []).filter((option) => !EXCLUDED_STATUS_UPDATE_VALUES.has(option?.value));
}

function getYearTotalHelpText(row, tableName) {
    if (usesCumulativeAverageHeadcount(row, tableName)) {
        return 'Avg / Total = cumulative average headcount across Jan-Dec running totals.';
    }
    if (row.summaryMode === 'blank') {
        return '';
    }
    if (row.summaryMode === 'avg') {
        return 'Avg / Total = average of Jan-Dec values.';
    }
    if (row.summaryMode === 'last') {
        return 'Avg / Total = December value.';
    }
    return 'Avg / Total = sum of Jan-Dec values.';
}

function getBaseFormulaKey(rowKey) {
    if (!rowKey) {
        return '';
    }
    if (rowKey.startsWith('combinedAbsence-')) return 'combinedAbsence';
    if (rowKey.startsWith('scheduledOvertime-')) return 'scheduledOvertime';
    if (rowKey.startsWith('additionalStraightTime-')) return 'additionalStraightTime';
    if (rowKey.startsWith('stHours-')) return 'stHours';
    if (rowKey.startsWith('nsotHours-')) return 'nsotHours';
    if (rowKey.startsWith('totalHours-')) return 'totalHours';
    if (rowKey.startsWith('astadj-')) return 'additionalStraightTimeAdjustment';
    if (rowKey.startsWith('vac-')) return 'vacationCoverage';
    return rowKey;
}

function getAdditionalStraightJustificationRowKey() {
    return 'astjust-monthly';
}

function getVacationCoverageMarker(vacationCoverageConfig, rowKey, monthKey) {
    if (!vacationCoverageConfig || rowKey !== 'vac-ots') {
        return null;
    }
    if (monthKey === vacationCoverageConfig.entryMonthKey) {
        return {
            label: 'Entry',
            className: 'vacation-marker vacation-marker_entry',
            tooltip: 'Auto-populated positive Vacation Coverage entry month for Assembly OTS.'
        };
    }
    if (monthKey === vacationCoverageConfig.exitMonthKey) {
        return {
            label: 'Exit',
            className: 'vacation-marker vacation-marker_exit',
            tooltip: 'Auto-populated negative Vacation Coverage exit month for Assembly OTS.'
        };
    }
    return null;
}

const NON_DRIVER_ROW_DEFS = [
    {
        key: 'crews',
        driver: 'Number of Crews',
        classification: 'Shared',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'shifts',
        driver: 'Number of Shifts',
        classification: 'Shared',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'netJph',
        driver: 'Net / Net JPH',
        classification: 'Shared',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'calcVolume',
        driver: 'Calculated Volume incl. SOT days',
        classification: 'Calculated',
        valueType: 'number',
        summaryMode: 'sum',
        editable: false,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'scheduledVolume',
        driver: 'Scheduled Volume',
        classification: 'Mschedule',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'volumeVariance',
        driver: 'Scheduled Volume minus Calculated Volume',
        classification: 'Calculated',
        valueType: 'number',
        summaryMode: 'sum',
        editable: false,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'paidHoursPerCrew',
        driver: 'Paid Hours Per CREW',
        classification: 'Shared',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'availableDays',
        driver: 'Available Working Days / Month',
        classification: 'Shared',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: true,
        values: { ...EMPTY_MONTH_VALUES }
    },
    {
        key: 'productionDays',
        driver: 'Production Working Days / Month',
        classification: 'Shared',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: true,
        values: { ...EMPTY_MONTH_VALUES }
    },
    {
        key: 'eqSotDays',
        driver: 'EQ SOT Days',
        classification: 'Shared',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: true,
        values: { ...EMPTY_MONTH_VALUES }
    },
    {
        key: 'absenteeism-ots',
        driver: 'Absenteeism %',
        classification: 'OTS',
        valueType: 'percent',
        summaryMode: 'avg',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'absenteeism-skilled',
        driver: 'Absenteeism %',
        classification: 'Skilled',
        valueType: 'percent',
        summaryMode: 'avg',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'absenteeism-salaried',
        driver: 'Absenteeism %',
        classification: 'Salaried',
        valueType: 'percent',
        summaryMode: 'avg',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'nsot-ots',
        driver: 'NSOT % = NSOT / (ST + SOT)',
        classification: 'OTS',
        valueType: 'percent',
        summaryMode: 'avg',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'nsot-skilled',
        driver: 'NSOT % = NSOT / (ST + SOT)',
        classification: 'Skilled',
        valueType: 'percent',
        summaryMode: 'avg',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'nsot-salaried',
        driver: 'NSOT % = NSOT / (ST + SOT)',
        classification: 'Salaried',
        valueType: 'percent',
        summaryMode: 'avg',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    }
];

const GPS_NON_DRIVER_ROW_DEFS = [
    {
        key: 'gpsFinalAssemblyLineJph',
        driver: 'Final Assembly Line JPH',
        classification: 'Shared',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'gpsDailyOpPlanVolume',
        driver: 'Daily Op Plan Volume',
        classification: 'Shared',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'gpsSotDaysWeekends',
        driver: 'SOT days (Weekends)',
        classification: 'Shared',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'gpsTotalSotDays',
        driver: 'Total SOT Days',
        classification: 'Calculated',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: false,
        values: { ...ZERO_MONTH_VALUES }
    }
];

const STAMPING_NON_DRIVER_ROW_DEFS = [
    {
        key: 'stampingEquivalentUnitsVolume',
        driver: 'Equivalent Units Volume',
        classification: 'Shared',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'stampingDailyOpPlanVolume',
        driver: 'Daily Op Plan Volume',
        classification: 'Shared',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'stampingHarbourStrokesHpu',
        driver: 'HARBOUR STROKES HPU',
        classification: 'Shared',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'stampingScheduledVolumePieces',
        driver: 'Scheduled Volume Pieces',
        classification: 'Shared',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'stampingScheduledVolumeStrokes',
        driver: 'Scheduled Volume Strokes',
        classification: 'Shared',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'stampingEquivalentSotPct',
        driver: 'Equivalent SOT %',
        classification: 'Shared',
        valueType: 'percent',
        summaryMode: 'avg',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'stampingSotPercentWeekendDays',
        driver: 'SOT percent from weekend days',
        classification: 'Shared',
        valueType: 'percent',
        summaryMode: 'avg',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'stampingSotFromLineTime',
        driver: 'SOT from line time',
        classification: 'Shared',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'stampingSotEquivalentDaysTotal',
        driver: 'SOT equivalent days total',
        classification: 'Calculated',
        formulaKey: 'stampingSotEquivalentDaysTotal',
        valueType: 'decimal',
        summaryMode: 'sum',
        editable: false,
        values: { ...ZERO_MONTH_VALUES }
    }
];

const DRIVER_ROW_DEFS = [
    {
        key: 'base-ots',
        category: 'Base Headcount',
        driver: 'Base Headcount (non SUPP, no Apprentices)',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'avg',
        editable: false,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'base-skilled',
        category: 'Base Headcount',
        driver: 'Base Headcount (non SUPP, no Apprentices)',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'avg',
        editable: false,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'base-salaried',
        category: 'Base Headcount',
        driver: 'Base Headcount (non SUPP, no Apprentices)',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'avg',
        editable: false,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'approved-ots',
        category: '2025 Approved Target Changes',
        driver: 'Approved Target Changes',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'approved-skilled',
        category: '2025 Approved Target Changes',
        driver: 'Approved Target Changes',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'approved-salaried',
        category: '2025 Approved Target Changes',
        driver: 'Approved Target Changes',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'prod-ots',
        category: 'Adjustments',
        driver: 'Productivity',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'prod-skilled',
        category: 'Adjustments',
        driver: 'Productivity',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'prod-salaried',
        category: 'Adjustments',
        driver: 'Productivity',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'mbc-ots',
        category: 'Adjustments',
        driver: 'MBC',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'mbc-skilled',
        category: 'Adjustments',
        driver: 'MBC',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'mbc-salaried',
        category: 'Adjustments',
        driver: 'MBC',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'lms-ots',
        category: 'Adjustments',
        driver: 'LMS',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'lms-skilled',
        category: 'Adjustments',
        driver: 'LMS',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'lms-salaried',
        category: 'Adjustments',
        driver: 'LMS',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'vac-ots',
        category: 'Adjustments',
        driver: 'Vacation Coverage',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'vac-skilled',
        category: 'Adjustments',
        driver: 'Vacation Coverage',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'vac-salaried',
        category: 'Adjustments',
        driver: 'Vacation Coverage',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'content-ots',
        category: 'Adjustments',
        driver: 'Content Changes',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'content-skilled',
        category: 'Adjustments',
        driver: 'Content Changes',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'content-salaried',
        category: 'Adjustments',
        driver: 'Content Changes',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'sourcing-ots',
        category: 'Adjustments',
        driver: 'Sourcing',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'sourcing-skilled',
        category: 'Adjustments',
        driver: 'Sourcing',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'sourcing-salaried',
        category: 'Adjustments',
        driver: 'Sourcing',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'mfgopt-ots',
        category: 'Adjustments',
        driver: 'Mfg Opt',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'mfgopt-skilled',
        category: 'Adjustments',
        driver: 'Mfg Opt',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'mfgopt-salaried',
        category: 'Adjustments',
        driver: 'Mfg Opt',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'opplan-ots',
        category: 'Adjustments',
        driver: 'Op Plan',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'opplan-skilled',
        category: 'Adjustments',
        driver: 'Op Plan',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'opplan-salaried',
        category: 'Adjustments',
        driver: 'Op Plan',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'launch-ots',
        category: 'Adjustments',
        driver: 'Launch',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'launch-skilled',
        category: 'Adjustments',
        driver: 'Launch',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'launch-salaried',
        category: 'Adjustments',
        driver: 'Launch',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'containment-ots',
        category: 'Adjustments',
        driver: 'Containment',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'containment-skilled',
        category: 'Adjustments',
        driver: 'Containment',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'containment-salaried',
        category: 'Adjustments',
        driver: 'Containment',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'others-ots',
        category: 'Adjustments',
        driver: 'Other / Excess',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'others-skilled',
        category: 'Adjustments',
        driver: 'Other / Excess',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'others-salaried',
        category: 'Adjustments',
        driver: 'Other / Excess',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'astadj-ots',
        category: 'Hours Adjustments',
        driver: 'Additional ST Adjustment',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'astadj-skilled',
        category: 'Hours Adjustments',
        driver: 'Additional ST Adjustment',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'astadj-salaried',
        category: 'Hours Adjustments',
        driver: 'Additional ST Adjustment',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'sum',
        editable: true,
        values: { prevDec: 0, jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }
    },
    {
        key: 'total-ots',
        category: 'Total Manpower',
        driver: 'Total Manpower (Include Target Changes)',
        classification: 'OTS',
        valueType: 'number',
        summaryMode: 'avg',
        editable: false,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'total-skilled',
        category: 'Total Manpower',
        driver: 'Total Manpower (Include Target Changes)',
        classification: 'Skilled',
        valueType: 'number',
        summaryMode: 'avg',
        editable: false,
        values: { ...ZERO_MONTH_VALUES }
    },
    {
        key: 'total-salaried',
        category: 'Total Manpower',
        driver: 'Total Manpower (Include Target Changes)',
        classification: 'Salaried',
        valueType: 'number',
        summaryMode: 'avg',
        editable: false,
        values: { ...ZERO_MONTH_VALUES }
    }
];

function cloneRows(rows) {
    return rows.map((row) => ({
        ...row,
        // When a month record does not exist yet, render editable inputs as blank
        // (null) instead of defaulting them to zero to avoid implying saved data.
        values: row.editable
            ? { ...EMPTY_MONTH_VALUES }
            : { ...(row.values || ZERO_MONTH_VALUES) }
    }));
}

export function normalizeSectorKey(sector) {
    const normalized = String(sector || '').trim().toLowerCase();
    if (normalized.includes('gps')) {
        return 'gps';
    }
    if (normalized.includes('stamp') || normalized.includes('press')) {
        return 'stamping';
    }
    return 'assembly';
}

function getSectorSpecificNonDriverDefs(sector) {
    const sectorKey = normalizeSectorKey(sector);
    if (sectorKey === 'gps') {
        return GPS_NON_DRIVER_ROW_DEFS;
    }
    if (sectorKey === 'stamping') {
        return STAMPING_NON_DRIVER_ROW_DEFS;
    }
    return [];
}

function getBaseNonDriverDefs(sector) {
    return NON_DRIVER_ROW_DEFS;
}

function round(value, precision = 1) {
    const factor = 10 ** precision;
    return Math.round((Number(value) || 0) * factor) / factor;
}

export function truncate(value, precision = 1) {
    const factor = 10 ** precision;
    return Math.trunc((Number(value) || 0) * factor) / factor;
}

function sumMonths(values) {
    return MONTH_COLUMNS
        .filter((column) => column.key !== 'prevDec')
        .reduce((total, column) => total + (Number(values[column.key]) || 0), 0);
}

function isEmptyMonthValue(value) {
    return value === null || value === undefined || value === '';
}

function isZeroLikeNumericValue(value) {
    return !isEmptyMonthValue(value) && Number(value) === 0;
}

function hasAnyNonEmptyValue(values) {
    return (values || []).some((value) => !isEmptyMonthValue(value));
}

function hasAnyMonthValue(values) {
    return MONTH_COLUMNS.some((column) => !isEmptyMonthValue(values?.[column.key]));
}

function monthKeysThrough(monthKey) {
    const keys = MONTH_COLUMNS
        .filter((column) => column.key !== 'prevDec')
        .map((column) => column.key);
    const index = keys.indexOf(monthKey);
    return index === -1 ? [] : keys.slice(0, index + 1);
}

function sumMonthsThrough(values, monthKey) {
    return monthKeysThrough(monthKey).reduce((total, key) => total + (Number(values[key]) || 0), 0);
}

export function buildCumulativeTotalValues(previousDecemberTotal, approvedValues, adjustmentRowsByKey) {
    const nextValues = {
        prevDec: Number(previousDecemberTotal) || 0
    };
    let runningTotal = Number(previousDecemberTotal) || 0;

    MONTH_COLUMNS
        .filter((column) => column.key !== 'prevDec')
        .forEach((column) => {
            const adjustmentTotal = Object.values(adjustmentRowsByKey || {}).reduce(
                (total, rowValues) => total + (Number(rowValues?.[column.key]) || 0),
                0
            );
            runningTotal += (Number(approvedValues?.[column.key]) || 0) + adjustmentTotal;
            nextValues[column.key] = runningTotal;
        });

    return nextValues;
}

export function buildTotalManpowerValues(baseValues, approvedValues, adjustmentRowsByKey) {
    const nextValues = {};
    const basePrevDec = Number(baseValues?.prevDec) || 0;
    const approvedPrevDec = Number(approvedValues?.prevDec) || 0;
    const previousDecemberTotal = basePrevDec + approvedPrevDec;
    // Previous December combines the prior-year published December baselines for
    // base headcount and approved target changes.
    // Jan-Dec show the previous December total plus same-classification adjustment rows
    // for that month, excluding current-month base headcount and approved target values.
    nextValues.prevDec = previousDecemberTotal;
    let runningTotal = previousDecemberTotal;

    MONTH_COLUMNS
        .filter((column) => column.key !== 'prevDec')
        .forEach((column) => {
            const adjustmentTotal = Object.values(adjustmentRowsByKey || {}).reduce(
                (total, rowValues) => total + (Number(rowValues?.[column.key]) || 0),
                0
            );
            runningTotal += adjustmentTotal;
            nextValues[column.key] = runningTotal;
        });

    return nextValues;
}

export function buildAssemblyVacationCoverageValues({
    sector,
    classification,
    vacationPercent = 0,
    entryMonthKey,
    exitMonthKey,
    currentValues = {},
    baseValues = {},
    approvedValues = {},
    adjustmentRowsByKey = {}
}) {
    // Start from current user-edited values for non-locked months.
    // The entry and exit month cells are always fully recalculated (not preserved
    // from currentValues) to prevent accumulation across repeated recalc calls.
    const nextValues = {
        ...ZERO_MONTH_VALUES,
        ...currentValues
    };

    if (normalizeSectorKey(sector) !== 'assembly' || classification !== 'OTS') {
        return nextValues;
    }

    const percent = Number(vacationPercent) || 0;
    if (percent <= 0 || !entryMonthKey || !exitMonthKey) {
        return nextValues;
    }

    const totalBeforeVacation = buildTotalManpowerValues(baseValues, approvedValues, adjustmentRowsByKey);
    const entryBase = Number(totalBeforeVacation?.[entryMonthKey]) || 0;
    const seededValue = Math.round(entryBase * (percent / 100));

    // Always set entry and exit to their derived values (never accumulate).
    if (Object.prototype.hasOwnProperty.call(nextValues, entryMonthKey)) {
        nextValues[entryMonthKey] = seededValue;
    }
    if (Object.prototype.hasOwnProperty.call(nextValues, exitMonthKey)) {
        nextValues[exitMonthKey] = -seededValue;
    }

    return nextValues;
}

export function calculateHourMetrics({
    totalManpower = 0,
    absenteeismPct = 0,
    nsotPct = 0,
    paidHoursPerCrew = 0,
    availableDays = 0,
    productionDays = 0,
    eqSotDays = 0,
    crews = 1,
    shifts = 0,
    vacationValues = {},
    monthKey,
    classification,
    additionalStraightAdjustment = 0
}) {
    const ratio = Number(crews) === 0 ? 0 : (Number(shifts) || 0) / Number(crews);
    const summerVroDenominator = Number(totalManpower);
    const summerVroPct = summerVroDenominator <= 0
        ? 0
        : Math.max(0, sumMonthsThrough(vacationValues, monthKey)) / summerVroDenominator;
    const combinedAbsence = Number(absenteeismPct) + summerVroPct;
    const productiveManpower = Number(totalManpower) * Math.max(0, 1 - combinedAbsence);
    const scheduledOvertime = productiveManpower * Number(paidHoursPerCrew) * Number(eqSotDays) * ratio;
    const additionalStraightFormula = Number(totalManpower) *
        Math.max(0, 1 - Number(absenteeismPct)) *
        ratio *
        Number(paidHoursPerCrew) *
        classificationMultiplier(classification) *
        (Number(availableDays) - Number(productionDays));
    const additionalStraightTime = additionalStraightFormula + Number(additionalStraightAdjustment || 0);
    const stHours = (productiveManpower * Number(paidHoursPerCrew) * Number(productionDays) * ratio) + additionalStraightTime;
    const nsotHours = (stHours + scheduledOvertime) * Number(nsotPct);
    const totalHours = stHours + scheduledOvertime + nsotHours;

    return {
        combinedAbsence: round(combinedAbsence * 100, 1),
        scheduledOvertime: round(scheduledOvertime, 1),
        additionalStraightTime: round(additionalStraightTime, 1),
        stHours: round(stHours, 1),
        nsotHours: round(nsotHours, 1),
        totalHours: round(totalHours, 1)
    };
}

export function averageMonths(values) {
    return truncate(sumMonths(values) / 12, 1);
}

export function buildGpsTotalSotDaysValues(weekendValues = {}, eqSotDaysValues = {}) {
    const values = {};
    MONTH_COLUMNS.forEach((column) => {
        const weekend = weekendValues?.[column.key];
        const eqSotDays = eqSotDaysValues?.[column.key];
        const hasData = !isEmptyMonthValue(weekend) || !isEmptyMonthValue(eqSotDays);
        values[column.key] = hasData
            ? (Number(weekend) || 0) + (Number(eqSotDays) || 0)
            : null;
    });
    return values;
}

export function buildStampingSotEquivalentDaysTotalValues(productionDaysValues = {}, equivalentSotPercentValues = {}) {
    const values = {};
    MONTH_COLUMNS.forEach((column) => {
        const productionDaysRaw = productionDaysValues?.[column.key];
        const equivalentSotPercentRaw = equivalentSotPercentValues?.[column.key];
        const hasData = !isEmptyMonthValue(productionDaysRaw) || !isEmptyMonthValue(equivalentSotPercentRaw);
        if (!hasData) {
            values[column.key] = null;
            return;
        }
        const productionDays = Number(productionDaysRaw) || 0;
        const equivalentSotPercent = Number(equivalentSotPercentRaw) || 0;
        values[column.key] = round(productionDays * (equivalentSotPercent / 100), 1);
    });
    return values;
}

function weightedAverage(values) {
    if (!hasAnyNonEmptyValue(values.map((item) => item?.value))) {
        return null;
    }
    const totals = values.reduce(
        (acc, item) => {
            const weight = Number(item.weight) || 0;
            const value = Number(item.value) || 0;
            acc.weighted += value * weight;
            acc.weight += weight;
            return acc;
        },
        { weighted: 0, weight: 0 }
    );

    return totals.weight === 0 ? 0 : totals.weighted / totals.weight;
}

function formatValue(value, valueType) {
    if (valueType === 'text') {
        return String(value || '—');
    }

    if (value === null || value === undefined || value === '') {
        return '';
    }

    if (isZeroLikeNumericValue(value)) {
        return '';
    }

    const numericValue = Number(value) || 0;

    if (valueType === 'decimal') {
        return numericValue.toLocaleString('en-US', {
            minimumFractionDigits: 1,
            maximumFractionDigits: 1
        });
    }

    if (valueType === 'percent') {
        return `${numericValue.toLocaleString('en-US', {
            minimumFractionDigits: 1,
            maximumFractionDigits: 1
        })}%`;
    }

    return numericValue.toLocaleString('en-US');
}

function summaryValue(row) {
    if (row.summaryMode === 'blank') {
        return '—';
    }

    if (!hasAnyMonthValue(row.values)) {
        return '';
    }

    if (row.summaryMode === 'last') {
        return formatValue(row.values.dec, row.valueType);
    }

    if (row.summaryMode === 'avg') {
        return formatValue(averageMonths(row.values), row.valueType);
    }

    return formatValue(sumMonths(row.values), row.valueType);
}

function cumulativeAverage(values) {
    let runningTotal = 0;
    let monthCount = 0;
    let cumulativeSum = 0;

    MONTH_COLUMNS
        .filter((column) => column.key !== 'prevDec')
        .forEach((column) => {
            runningTotal += Number(values?.[column.key]) || 0;
            cumulativeSum += runningTotal;
            monthCount += 1;
        });

    return monthCount ? cumulativeSum / monthCount : 0;
}

function usesCumulativeAverageHeadcount(row, tableName) {
    return tableName === 'driver'
        && row?.category === 'Adjustments'
        && CUMULATIVE_AVERAGE_HC_DRIVERS.has(row.driver);
}

function toVariancePercent(value, total) {
    if (!total) {
        return '0.0%';
    }

    return `${round((value / total) * 100, 1)}%`;
}

function percentToDecimal(value) {
    return (Number(value) || 0) / 100;
}

function classificationMultiplier(classification) {
    if (classification === 'OTS') {
        return 0.2;
    }

    if (classification === 'Skilled') {
        return 0.95;
    }

    return 0;
}

function parsePercentString(value) {
    return Number(String(value || '').replace('%', '').replace(/,/g, '')) || 0;
}

function rowMatchesQuickFilter(row, selectedQuickFilter) {
    if (!selectedQuickFilter || selectedQuickFilter === 'all') {
        return true;
    }

    if (selectedQuickFilter === 'highVariance') {
        return Math.abs(parsePercentString(row.variance)) >= 5;
    }

    if (selectedQuickFilter === 'adjustmentsOnly') {
        return ['OTS Avg HC', 'Skilled Avg HC', 'Salaried Avg HC', 'Buffer to Plan', 'Volume Variance'].includes(row.metric);
    }

    if (selectedQuickFilter === 'showCalculated') {
        return ['Scheduled Volume', 'Calculated Volume', 'Volume Variance', 'Production Days', 'EQ SOT Days'].includes(row.metric);
    }

    return true;
}

function rowMatchesPinnedKpi(row, selectedPinnedKpi) {
    if (!selectedPinnedKpi) {
        return false;
    }

    if (selectedPinnedKpi === 'scheduledVolumeVariance') {
        return row.metric === 'Volume Variance';
    }

    if (selectedPinnedKpi === 'prodPct') {
        return row.metric === 'Buffer to Plan';
    }

    if (selectedPinnedKpi === 'averageHc') {
        return row.metric.includes('Avg HC');
    }

    if (selectedPinnedKpi === 'volumeVsPlan') {
        return row.metric === 'Scheduled Volume' || row.metric === 'Calculated Volume';
    }

    if (selectedPinnedKpi === 'readyForPublish') {
        return row.metric === 'Production Days' || row.metric === 'EQ SOT Days';
    }

    return false;
}

export default class GwbBudgetWorkbench extends NavigationMixin(LightningElement) {
    @api recordId;
    @api plantAdminPermissionOverride;
    @api industrialEngineerPermissionOverride;
    @api systemAdminPermissionOverride;
    contextPlantId;

    activeSectionNames = [...OPEN_SECTIONS];
    nonDriverRows = cloneRows(NON_DRIVER_ROW_DEFS);
    driverRows = cloneRows(DRIVER_ROW_DEFS);
    budgetOptions = [];
    selectedBudgetId;
    selectedYear = '';
    selectedSector = '';
    selectedVersion = '';
    budgetHeader;
    errorMessage = '';
    isLoading = false;
    isSaving = false;
    cloneModalOpen = false;
    selectedCloneVersion = '';
    mScheduleOptions = [];
    isSavingComment = false;
    dirtyRowKeys = new Set();
    dirtyCellKeys = new Set();
    selectedQuickFilter = '';
    selectedDriverDefault = '';
    selectedClassificationFilter = 'All';
    selectedDriverFilter = 'All';
    nonDriverAbsenteeismExpanded = true;
    nonDriverNsotExpanded = true;
    selectedPinnedKpi = '';
    selectedScope = 'Assembly / Polymers';
    canEditCurrentBudget = false;
    commentRowsByCellKey = {};
    selectedCommentCell;
    commentDraft = '';
    commentMenuOpen = false;
    commentMenuStyle = '';
    commentModalOpen = false;
    statusModalOpen = false;
    statusOptions = [];
    selectedStatusValue = '';
    editingCommentId = null;
    sessionSavedCommentCellKeys = new Set();
    vacationCoverageConfig = null;
    isGuidedTableMode = false;
    activeViewTab = 'input';
    guidedSectionIndex = 0;
    accordionSectionNamesSnapshot = [...OPEN_SECTIONS];
    draftCellValues = {};
    connectedCallback() {
        this.initializeWorkbench();
    }

    get resolvedPlantAdminPermission() {
        return typeof this.plantAdminPermissionOverride === 'boolean'
            ? this.plantAdminPermissionOverride
            : hasPlantAdminPermission;
    }

    get resolvedIndustrialEngineerPermission() {
        return typeof this.industrialEngineerPermissionOverride === 'boolean'
            ? this.industrialEngineerPermissionOverride
            : hasIndustrialEngineerPermission;
    }

    get resolvedSystemAdminPermission() {
        return typeof this.systemAdminPermissionOverride === 'boolean'
            ? this.systemAdminPermissionOverride
            : hasGwbSystemAdminPermission;
    }

    debugLog(message, details) {
        return;
    }

    get monthColumns() {
        const budgetYear = Number(this.budgetHeader?.year || this.selectedYear);
        const previousYearSuffix = Number.isFinite(budgetYear) ? String(budgetYear - 1).slice(-2) : '25';

        return MONTH_COLUMNS.map((column) => (
            column.key === 'prevDec'
                ? { ...column, label: `Dec'${previousYearSuffix}` }
                : column
        ));
    }

    get classificationFilterOptions() {
        return [
            { label: 'All', value: 'All' },
            { label: 'OTS', value: 'OTS' },
            { label: 'Skilled', value: 'Skilled' },
            { label: 'Salaried', value: 'Salaried' }
        ];
    }

    get driverFilterOptions() {
        const labels = new Set(['All']);
        this.driverRows.forEach((row) => {
            if (!row?.driver) {
                return;
            }
            if (
                row.key?.startsWith('base-') ||
                row.key?.startsWith('approved-') ||
                row.key?.startsWith('astadj-') ||
                row.key?.startsWith('total-')
            ) {
                return;
            }
            if (row.driver) {
                labels.add(row.driver);
            }
        });
        return Array.from(labels).map((label) => ({ label, value: label }));
    }

    get hasAssemblyVacationCoverageConfig() {
        return normalizeSectorKey(this.budgetHeader?.sector || this.selectedSector) === 'assembly' && !!this.vacationCoverageConfig;
    }

    get nonDriverOpen() {
        return this.activeSectionNames.includes('nonDriver');
    }

    get nonDriverSectionToggleLabel() {
        return this.nonDriverOpen ? 'Collapse Section' : 'Expand Section';
    }

    get nonDriverIconClass() {
        return this.nonDriverOpen ? 'section-header__icon section-header__icon_open' : 'section-header__icon';
    }

    get driverOpen() {
        return this.activeSectionNames.includes('driver');
    }

    get driverSectionToggleLabel() {
        return this.driverOpen ? 'Collapse Section' : 'Expand Section';
    }

    get driverIconClass() {
        return this.driverOpen ? 'section-header__icon section-header__icon_open' : 'section-header__icon';
    }

    get hoursOpen() {
        return this.activeSectionNames.includes('hours');
    }

    get hoursSectionToggleLabel() {
        return this.hoursOpen ? 'Collapse Section' : 'Expand Section';
    }

    get hoursIconClass() {
        return this.hoursOpen ? 'section-header__icon section-header__icon_open' : 'section-header__icon';
    }

    get summaryOpen() {
        return this.activeSectionNames.includes('summary');
    }

    get summarySectionToggleLabel() {
        return this.summaryOpen ? 'Collapse Section' : 'Expand Section';
    }

    get summaryIconClass() {
        return this.summaryOpen ? 'section-header__icon section-header__icon_open' : 'section-header__icon';
    }

    get comparisonOpen() {
        return this.activeSectionNames.includes('comparison');
    }

    get comparisonSectionToggleLabel() {
        return this.comparisonOpen ? 'Collapse Section' : 'Expand Section';
    }

    get comparisonIconClass() {
        return this.comparisonOpen ? 'section-header__icon section-header__icon_open' : 'section-header__icon';
    }

    get hasBudgets() {
        return this.budgetOptions.length > 0;
    }

    get hasActiveBudget() {
        return !!this.activeBudgetId;
    }

    get selectedBudgetOption() {
        return this.budgetOptions.find((item) => item.id === this.activeBudgetId) || null;
    }

    get isCloneableTargetRecord() {
        const recordTypeDeveloperName =
            this.budgetHeader?.recordTypeDeveloperName ||
            this.selectedBudgetOption?.recordTypeDeveloperName ||
            '';
        return recordTypeDeveloperName === 'Target';
    }

    get showCloneButton() {
        return this.showStandardHeaderActions && !this.resolvedPlantAdminPermission && !this.resolvedIndustrialEngineerPermission;
    }

    get disableCreateDraft() {
        return !this.activeBudgetId || !this.isCloneableTargetRecord || this.isLoading || this.isSaving;
    }

    get disableCloneConfirm() {
        return !this.selectedCloneVersion || this.isLoading || this.isSaving;
    }

    get disableSave() {
        return !this.activeBudgetId || this.dirtyRowKeys.size === 0 || this.isSaving || this.isLoading || this.disableEditing;
    }

    get nonDriverSharedRowKeys() {
        return this.nonDriverRows
            .filter((row) => SHARED_ROW_META[row.key]?.persist)
            .map((row) => row.key);
    }

    get nonDriverClassificationRowKeys() {
        return this.nonDriverRows
            .filter((row) => (row.key.startsWith('absenteeism-') || row.key.startsWith('nsot-')) && SHARED_ROW_META[row.key]?.persist)
            .map((row) => row.key);
    }

    get driverEditableRowKeys() {
        return this.driverRows
            .filter((row) => !['Base Headcount', '2025 Approved Target Changes'].includes(row.category) && DRIVER_ROW_META[row.key]?.persist)
            .map((row) => row.key);
    }

    get disableNonDriverSharedSave() {
        return this.disableEditing || this.isSaving || this.isLoading || !this.hasDirtyRows(this.nonDriverSharedRowKeys);
    }

    get disableNonDriverClassificationSave() {
        return this.disableEditing || this.isSaving || this.isLoading || !this.hasDirtyRows(this.nonDriverClassificationRowKeys);
    }

    get disableDriverSave() {
        return this.disableEditing || this.isSaving || this.isLoading || !this.hasDirtyRows(this.driverEditableRowKeys);
    }

    get disableSelectors() {
        return this.isLoading;
    }

    get activeBudgetId() {
        return this.selectedBudgetId || this.budgetHeader?.id || null;
    }

    get disableEditing() {
        const status = this.budgetHeader?.status;
        return !this.activeBudgetId || this.isLoading || status === 'Published' || status === 'Locked' ||
            (this.resolvedPlantAdminPermission && status === 'Plant Review Complete');
    }

    get isTargetSplitPersona() {
        return this.resolvedPlantAdminPermission || this.resolvedSystemAdminPermission;
    }

    get isTargetSplitScopedStatus() {
        const status = this.budgetHeader?.status;
        return status === 'Published' || status === 'Locked';
    }

    get isTargetSplitMode() {
        return this.isTargetSplitPersona && this.isTargetSplitScopedStatus;
    }

    get showStandardHeaderActions() {
        return !this.isTargetSplitMode;
    }

    get canManageBudgetState() {
        const status = this.budgetHeader?.status;
        return !!this.activeBudgetId && status !== 'Published' && status !== 'Locked' &&
            !(this.resolvedPlantAdminPermission && status === 'Plant Review Complete');
    }

    get updateStatusDisabled() {
        return !this.canManageBudgetState || this.isSaving;
    }

    get readyForPublishDisabled() {
        return !this.canManageBudgetState || this.isSaving;
    }

    get disableStatusUpdateSave() {
        return this.isSaving || !this.activeBudgetId || !this.selectedStatusValue;
    }

    async handleUpdateStatus() {
        if (this.updateStatusDisabled) {
            return;
        }

        this.errorMessage = '';

        try {
            if (!this.statusOptions.length) {
                this.statusOptions = getAllowedStatusUpdateOptions(await getBudgetStatusOptions());
            }
            const currentStatus = this.budgetHeader?.status || '';
            this.selectedStatusValue = this.statusOptions.some((option) => option.value === currentStatus)
                ? currentStatus
                : '';
            this.statusModalOpen = true;
        } catch (error) {
            this.handleError(error, 'Unable to load the budget status options.');
        }
    }

    handleCloseStatusModal() {
        this.statusModalOpen = false;
        const currentStatus = this.budgetHeader?.status || '';
        this.selectedStatusValue = this.statusOptions.some((option) => option.value === currentStatus)
            ? currentStatus
            : '';
    }

    handleStatusValueChange(event) {
        this.selectedStatusValue = event.detail.value || '';
    }

    async handleSaveStatusUpdate() {
        if (this.disableStatusUpdateSave) {
            return;
        }

        this.isSaving = true;
        this.errorMessage = '';

        try {
            this.budgetHeader = await updateBudgetState({
                gwbYearId: this.activeBudgetId,
                nextStatus: this.selectedStatusValue
            });
            this.statusModalOpen = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Budget updated',
                    message: `This budget is now marked ${this.selectedStatusValue}.`,
                    variant: 'success'
                })
            );
            await this.initializeWorkbench();
        } catch (error) {
            this.handleError(error, 'Unable to update the budget state.');
        } finally {
            this.isSaving = false;
        }
    }

    get hasSelectedCommentCell() {
        return !!this.selectedCommentCell;
    }

    get selectedCommentContextItems() {
        if (!this.selectedCommentCell) {
            return [];
        }

        const items = [
            {
                key: 'table',
                label: 'Section',
                value:
                    this.selectedCommentCell.tableName === 'hoursJustification'
                        ? 'Hours Reason'
                        : this.selectedCommentCell.tableName === 'driver'
                            ? 'Manpower Adjustments'
                            : this.selectedCommentCell.tableName === 'hours'
                                ? 'Hour Calculations'
                                : 'Non-Driver Input Info'
            },
            {
                key: 'month',
                label: 'Month',
                value: this.selectedCommentCell.monthLabel
            }
        ];

        if (this.selectedCommentCell.classification && this.selectedCommentCell.classification !== 'Shared') {
            items.splice(1, 0, {
                key: 'classification',
                label: 'Classification',
                value: this.selectedCommentCell.classification
            });
        }

        return items;
    }

    get commentDraftLength() {
        return this.commentDraft?.length || 0;
    }

    get commentDraftHelperText() {
        if (!this.selectedCommentCell) {
            return 'Right-click any editable month cell to open comments for that exact value.';
        }

        if (this.selectedCommentCell.tableName === 'hoursJustification') {
            return 'Add one shared reason for this month. It is stored separately from normal cell comments.';
        }

        if (ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(this.selectedCommentCell.rowKey)) {
            return 'This is a normal cell comment on the adjustment value.';
        }

        return 'Capture the business reason, approver note, or assumption tied to this cell.';
    }

    get commentComposerTitle() {
        if (this.selectedCommentCell?.tableName === 'hoursJustification') {
            return 'Monthly reason';
        }
        return this.selectedCommentCell ? 'Comment on this value' : 'Comment composer';
    }

    get commentPrimaryActionLabel() {
        if (this.isSavingComment) {
            return 'Saving...';
        }
        if (this.selectedCommentCell?.tableName === 'hoursJustification') {
            return this.editingCommentId ? 'Update Reason' : 'Save Reason';
        }
        return this.editingCommentId ? 'Update Comment' : 'Save Comment';
    }

    get selectedCellComments() {
        if (!this.selectedCommentCell?.cellKey) {
            return [];
        }
        return this.commentRowsByCellKey[this.selectedCommentCell.cellKey] || [];
    }

    get hasSelectedCellComments() {
        return this.selectedCellComments.length > 0;
    }

    get recentComments() {
        return Object.values(this.commentRowsByCellKey)
            .flat()
            .sort((left, right) => {
                const leftTime = left?.createdDate ? new Date(left.createdDate).getTime() : 0;
                const rightTime = right?.createdDate ? new Date(right.createdDate).getTime() : 0;
                return rightTime - leftTime;
            })
            .slice(0, 5);
    }

    get activityGroups() {
        const groups = [];
        const now = new Date();
        this.recentComments.forEach((comment) => {
            const createdDate = comment?.createdDate ? new Date(comment.createdDate) : null;
            const label = createdDate
                ? createdDate.toLocaleString('en-US', { month: 'long', year: 'numeric' })
                : 'Recent';
            const subLabel = createdDate && createdDate.getMonth() === now.getMonth() && createdDate.getFullYear() === now.getFullYear()
                ? 'This Month'
                : '';
            let group = groups.find((item) => item.key === label);
            if (!group) {
                group = {
                    key: label,
                    label,
                    subLabel,
                    items: []
                };
                groups.push(group);
            }
            group.items.push(comment);
        });
        return groups;
    }

    get commentModalTitle() {
        if (!this.selectedCommentCell) {
            return 'Cell comments';
        }
        if (this.selectedCommentCell.tableName === 'hoursJustification') {
            return `${this.selectedCommentCell.rowLabel} · ${this.selectedCommentCell.monthLabel}`;
        }
        return `${this.selectedCommentCell.rowLabel} · ${this.selectedCommentCell.monthLabel}`;
    }

    get isEditingExistingComment() {
        return !!this.editingCommentId;
    }

    get commentPanelEmptyText() {
        if (this.disableEditing) {
            return 'No saved comments for this value.';
        }
        if (this.selectedCommentCell?.tableName === 'hoursJustification') {
            return 'No reason yet for this month. Add the required reason from the composer.';
        }
        return this.selectedCommentCell
            ? 'No comments yet for this value. Add the first note from the composer.'
            : 'No cell selected yet. Right-click a month cell to open comments.';
    }

    get canComposeComments() {
        return !this.disableEditing && !!this.selectedCommentCell;
    }

    get disableCommentSave() {
        return this.isSavingComment || this.disableEditing || !this.selectedCommentCell || !this.commentDraft.trim();
    }

    get showCommentActionInContextMenu() {
        return this.selectedCommentCell?.tableName !== 'hoursJustification';
    }

    get selectedCellSupportsJustification() {
        if (!this.selectedCommentCell) {
            return false;
        }
        if (this.selectedCommentCell.tableName === 'hoursJustification') {
            return this.selectedCommentCell.rowKey === getAdditionalStraightJustificationRowKey()
                && this.selectedCommentCell.monthKey !== 'prevDec';
        }
        return this.selectedCommentCell.tableName === 'driver'
            && ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(this.selectedCommentCell.rowKey)
            && this.selectedCommentCell.monthKey !== 'prevDec';
    }

    get justificationMenuActionLabel() {
        if (!this.selectedCommentCellSupportsJustification) {
            return 'Add Reason';
        }
        if (!this.showCommentActionInContextMenu) {
            return 'Edit Reason';
        }
        const monthKey = this.selectedCommentCell?.monthKey;
        const existingReason = monthKey ? this.getAdditionalStraightReasonComment(monthKey) : null;
        return existingReason ? 'Edit Reason' : 'Add Reason';
    }

    get guidedSectionCountLabel() {
        return `${this.guidedSectionIndex + 1} of ${SECTION_ORDER.length}`;
    }

    get guidedCurrentSectionName() {
        return SECTION_ORDER[this.guidedSectionIndex] || SECTION_ORDER[0];
    }

    get guidedCurrentSectionLabel() {
        return SECTION_LABELS[this.guidedCurrentSectionName] || 'Section';
    }

    get disableGuidedPrevious() {
        return this.guidedSectionIndex === 0;
    }

    get disableGuidedNext() {
        return this.guidedSectionIndex >= SECTION_ORDER.length - 1;
    }

    get isInputTab() {
        return this.activeViewTab === 'input';
    }

    get isSummaryTab() {
        return this.showSummaryTab && this.activeViewTab === 'summary';
    }

    get isAdjustmentsTab() {
        return this.showAdjustmentsTab && this.activeViewTab === 'adjustments';
    }

    get inputTabClass() {
        return this.isInputTab ? 'workbench-tab workbench-tab_active' : 'workbench-tab';
    }

    get summaryTabClass() {
        return this.isSummaryTab ? 'workbench-tab workbench-tab_active' : 'workbench-tab';
    }

    get adjustmentsTabClass() {
        return this.isAdjustmentsTab ? 'workbench-tab workbench-tab_active' : 'workbench-tab';
    }

    get showSummaryTab() {
        return !this.isTargetSplitMode;
    }

    get showAdjustmentsTab() {
        return this.isTargetSplitScopedStatus;
    }

    get canEditAdjustments() {
        return this.resolvedPlantAdminPermission || this.resolvedSystemAdminPermission;
    }

    get showNonDriverSection() {
        return this.isInputTab && (!this.isGuidedTableMode || this.guidedCurrentSectionName === 'nonDriver');
    }

    get showDriverSection() {
        return this.isInputTab && (!this.isGuidedTableMode || this.guidedCurrentSectionName === 'driver');
    }

    get showHoursSection() {
        return this.isInputTab && (!this.isGuidedTableMode || this.guidedCurrentSectionName === 'hours');
    }

    get showSummarySection() {
        return false;
    }

    get showComparisonSection() {
        return false;
    }

    normalizeActiveViewTab() {
        const allowedTabs = [
            'input',
            this.showSummaryTab ? 'summary' : null,
            this.showAdjustmentsTab ? 'adjustments' : null
        ].filter(Boolean);

        if (!allowedTabs.includes(this.activeViewTab)) {
            this.activeViewTab = this.showAdjustmentsTab ? 'adjustments' : 'input';
        }
    }

    get nonDriverRenderRows() {
        const sharedRows = this.nonDriverRows.filter((row) => {
            if (row.key.startsWith('absenteeism-') || row.key.startsWith('nsot-')) {
                return false;
            }
            return true;
        });
        return this.buildRenderRows(sharedRows, 'nonDriver').map((row) => ({
            ...row,
            classification: '',
            rowClass: this.getHighlightedRowClass(row.rowClass, row.driver)
        }));
    }

    get isStampingSector() {
        return normalizeSectorKey(this.budgetHeader?.sector || this.selectedSector) === 'stamping';
    }

    get isPlantAdminReviewMode() {
        const sectorKey = normalizeSectorKey(this.budgetHeader?.sector || this.selectedSector);
        return this.resolvedPlantAdminPermission &&
            this.budgetHeader?.status === 'Plant Review' &&
            sectorKey !== 'gps';
    }

    get nonDriverClassificationRows() {
        return [];
    }

    get driverRenderRows() {
        const visibleRows = this.driverRows.filter((row) => {
            if (row.key.startsWith('astadj-')) {
                return false;
            }
            if (row.key.startsWith('base-') || row.key.startsWith('approved-')) {
                return false;
            }
            if (this.selectedClassificationFilter !== 'All' && row.classification !== this.selectedClassificationFilter) {
                return false;
            }
            if (this.selectedDriverFilter !== 'All' && row.driver !== this.selectedDriverFilter) {
                return false;
            }
            return true;
        });

        const renderRows = this.buildRenderRows(visibleRows, 'driver').map((row) => {
            const isTotalManpowerRow = row.key.startsWith('total-');
            const isBaseHeadcountRow = row.key.startsWith('base-');
            const normalizedDriver = isTotalManpowerRow
                ? 'Total Manpower (Include Target Changes)'
                : row.driver;
            return {
                ...row,
                driverGroup: isTotalManpowerRow
                    ? 'total-manpower'
                    : isBaseHeadcountRow
                        ? 'base-headcount'
                        : normalizedDriver,
                driver: normalizedDriver,
                rowClass: this.getHighlightedRowClass(row.rowClass, normalizedDriver)
            };
        });

        const totalManpowerInsertIndex = renderRows.findIndex((row) => row.key === 'total-ots');
        if (totalManpowerInsertIndex >= 0) {
            const totalRow = this.buildRenderRows([{
                key: 'total-manpower-all',
                category: 'Total Manpower',
                driver: 'Total Manpower (Include Target Changes)',
                classification: 'Total',
                valueType: 'number',
                summaryMode: 'avg',
                editable: false,
                formulaKey: 'total-ots',
                values: this.totalManpowerMonthlyValues
            }], 'driver')[0];

            renderRows.splice(totalManpowerInsertIndex, 0, {
                ...totalRow,
                driverGroup: 'total-manpower',
                rowClass: this.getHighlightedRowClass(totalRow.rowClass, totalRow.driver)
            });
        }

        let displayIndex = 1;
        for (let index = 0; index < renderRows.length; index += 1) {
            const row = renderRows[index];
            const nextRow = renderRows[index + 1];
            const currentGroup = row.driverGroup || row.driver;
            const previousGroup = index > 0 ? (renderRows[index - 1].driverGroup || renderRows[index - 1].driver) : null;
            const nextGroup = nextRow ? (nextRow.driverGroup || nextRow.driver) : null;
            const isGroupStart = index === 0 || previousGroup !== currentGroup;
            const isGroupEnd = !nextRow || nextGroup !== currentGroup;

            if (isGroupStart) {
                let rowSpan = 1;
                for (let cursor = index + 1; cursor < renderRows.length; cursor += 1) {
                    const cursorGroup = renderRows[cursor].driverGroup || renderRows[cursor].driver;
                    if (cursorGroup !== currentGroup) {
                        break;
                    }
                    rowSpan += 1;
                }

                row.showDriverGroup = true;
                row.driverRowSpan = rowSpan;
                row.displayRowNumber = displayIndex;
                displayIndex += 1;
            } else {
                row.showDriverGroup = false;
                row.driverRowSpan = 0;
                row.displayRowNumber = '';
            }

            row.rowClass = `${row.rowClass} ${isGroupEnd ? 'driver-group-divider' : ''}`.trim();
        }

        return renderRows;
    }

    get hourCalculationRows() {
        const classifications = ['OTS', 'Skilled', 'Salaried'];
        const buildHoursInputGroup = (rowKeys, totalValueBuilder) => {
            const sourceRows = rowKeys
                .map((key) => this.findRow(this.nonDriverRows, key))
                .filter((row) => !!row)
                .map((row) => ({
                    ...row,
                    tableNameOverride: 'nonDriver',
                    editable: true,
                    summaryMode: 'avg'
                }));

            if (!sourceRows.length) {
                return [];
            }

            const totalValues = {};
            MONTH_COLUMNS.forEach((column) => {
                totalValues[column.key] = totalValueBuilder(column.key);
            });

            return [
                {
                    key: `${sourceRows[0].key.split('-')[0]}-total`,
                    driver: sourceRows[0].driver,
                    classification: 'Total',
                    valueType: sourceRows[0].valueType,
                    summaryMode: 'avg',
                    editable: false,
                    values: totalValues,
                    tableNameOverride: 'nonDriver',
                    formulaKey:
                        sourceRows[0].key.startsWith('absenteeism-')
                            ? 'absenteeism'
                            : sourceRows[0].key.startsWith('nsot-')
                                ? 'nsot'
                                : getBaseFormulaKey(sourceRows[0].key)
                },
                ...sourceRows
            ];
        };

        const getTotalManpowerForClassification = (classification, monthKey) => {
            const rowKey = `total-${classification.toLowerCase()}`;
            return Number(this.findRow(this.driverRows, rowKey)?.values?.[monthKey]) || 0;
        };

        const inputRows = [
            ...buildHoursInputGroup(
                ['absenteeism-ots', 'absenteeism-skilled', 'absenteeism-salaried'],
                (monthKey) =>
                    weightedAverage(
                        classifications.map((classification) => ({
                            value: this.findRow(this.nonDriverRows, `absenteeism-${classification.toLowerCase()}`)?.values?.[monthKey],
                            weight: getTotalManpowerForClassification(classification, monthKey)
                        }))
                    )
            ),
            ...buildHoursInputGroup(
                ['nsot-ots', 'nsot-skilled', 'nsot-salaried'],
                (monthKey) => {
                    const totalNsot = classifications.reduce(
                        (sum, classification) => sum + (this.calculateHoursForMonth(classification, monthKey).nsotHours || 0),
                        0
                    );
                    const totalSt = classifications.reduce(
                        (sum, classification) => sum + (this.calculateHoursForMonth(classification, monthKey).stHours || 0),
                        0
                    );
                    const totalSot = classifications.reduce(
                        (sum, classification) => sum + (this.calculateHoursForMonth(classification, monthKey).scheduledOvertime || 0),
                        0
                    );
                    return totalSt + totalSot === 0 ? 0 : (totalNsot / (totalSt + totalSot)) * 100;
                }
            )
        ];
        const additionalStraightAdjustmentRows = ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS
            .map((key) => {
                const source = this.findRow(this.driverRows, key);
                if (!source) {
                    return null;
                }
                return {
                    ...source,
                    driver: 'Additional Straight Time Hours Adjustment',
                    tableNameOverride: 'driver',
                    editable: true,
                    summaryMode: 'sum'
                };
            })
            .filter((row) => !!row);
        const additionalStraightJustificationRows = additionalStraightAdjustmentRows.length
            ? [{
                key: getAdditionalStraightJustificationRowKey(),
                category: 'Hours Adjustments',
                driver: ADDITIONAL_ST_JUSTIFICATION_LABEL,
                classification: 'Shared',
                valueType: 'text',
                summaryMode: 'blank',
                editable: false,
                tableNameOverride: 'hoursJustification',
                values: (() => {
                    const values = { prevDec: '' };
                    MONTH_COLUMNS
                        .filter((column) => column.key !== 'prevDec')
                        .forEach((column) => {
                            const justificationComment =
                                this.getAdditionalStraightReasonComment(column.key);
                            const hasAdjustments = additionalStraightAdjustmentRows.some(
                                (row) => (Number(row.values?.[column.key]) || 0) !== 0
                            );
                            values[column.key] = justificationComment?.commentText || (hasAdjustments ? 'Required' : '');
                        });
                    return values;
                })(),
                formulaKey: 'additionalStraightTimeAdjustment'
            }]
            : [];

        const rowConfigs = [
            { key: 'combinedAbsence', label: 'Absenteeism % + Summer VRO %', valueType: 'percent', summaryMode: 'avg' },
            { key: 'scheduledOvertime', label: 'Scheduled Overtime Hours', valueType: 'number', summaryMode: 'sum' },
            { key: 'additionalStraightTime', label: "Additional Straight Time Hours", valueType: 'number', summaryMode: 'sum' },
            { key: 'stHours', label: "ST Hours (inc. Add'l ST Hours)", valueType: 'number', summaryMode: 'sum' },
            { key: 'nsotHours', label: 'NSOT Hours', valueType: 'number', summaryMode: 'sum' },
            { key: 'totalHours', label: 'Total Hours', valueType: 'number', summaryMode: 'sum' }
        ];

        const rows = [...inputRows];

        rowConfigs.forEach((config) => {
            if (config.key === 'additionalStraightTime') {
                rows.push(...additionalStraightAdjustmentRows);
                rows.push(...additionalStraightJustificationRows);
            }

            const totalValues = {};
            MONTH_COLUMNS.forEach((column) => {
                if (config.valueType === 'percent') {
                    totalValues[column.key] = weightedAverage(
                        classifications.map((classification) => ({
                            value: this.calculateHoursForMonth(classification, column.key)[config.key],
                            weight: getTotalManpowerForClassification(classification, column.key)
                        }))
                    );
                    return;
                }

                const valuesByClassification = classifications
                    .map((classification) => this.calculateHoursForMonth(classification, column.key)[config.key]);
                if (!hasAnyNonEmptyValue(valuesByClassification)) {
                    totalValues[column.key] = null;
                    return;
                }
                totalValues[column.key] = valuesByClassification.reduce(
                    (total, value) => total + (Number(value) || 0),
                    0
                );
            });

            rows.push({
                key: `${config.key}-all`,
                driver: config.label,
                classification: 'Total',
                valueType: config.valueType,
                summaryMode: config.summaryMode,
                editable: false,
                values: totalValues,
                formulaKey: config.key
            });

            classifications.forEach((classification) => {
                const values = {};

                MONTH_COLUMNS.forEach((column) => {
                    values[column.key] = this.calculateHoursForMonth(classification, column.key)[config.key];
                });

                rows.push({
                    key: `${config.key}-${classification.toLowerCase()}`,
                    driver: config.label,
                    classification,
                    valueType: config.valueType,
                    summaryMode: config.summaryMode,
                    editable: false,
                    values
                });
            });
        });

        const filteredRows = rows.filter((row) => {
            if (this.selectedClassificationFilter === 'All') {
                return true;
            }
            return row.classification === this.selectedClassificationFilter || row.classification === 'Shared';
        });

        const renderRows = this.buildRenderRows(filteredRows, 'hours').map((row) => ({
            ...row,
            rowClass: this.getHighlightedRowClass(row.rowClass, row.driver)
        }));

        let displayIndex = 1;
        for (let index = 0; index < renderRows.length; index += 1) {
            const row = renderRows[index];
            const nextRow = renderRows[index + 1];
            const isGroupStart = index === 0 || renderRows[index - 1].driver !== row.driver;
            const isGroupEnd = !nextRow || nextRow.driver !== row.driver;

            if (isGroupStart) {
                let rowSpan = 1;
                for (let cursor = index + 1; cursor < renderRows.length; cursor += 1) {
                    if (renderRows[cursor].driver !== row.driver) {
                        break;
                    }
                    rowSpan += 1;
                }

                row.showDriverGroup = true;
                row.driverRowSpan = rowSpan;
                row.displayRowNumber = displayIndex;
                displayIndex += 1;
            } else {
                row.showDriverGroup = false;
                row.driverRowSpan = 0;
                row.displayRowNumber = '';
            }

            row.rowClass = `${row.rowClass} ${isGroupEnd ? 'driver-group-divider' : ''}`.trim();
        }

        return renderRows;
    }

    get targetPageTitle() {
        const plant = this.budgetHeader?.plantName || 'Target';
        const year = this.budgetHeader?.year || this.selectedYear || '';
        const mSchedule = this.budgetHeader?.mScheduleVersion || this.selectedVersion || '';
        const titleSuffix = [year, mSchedule].filter(Boolean).join(' ');
        return titleSuffix ? `${plant} - ${titleSuffix}` : plant;
    }

    get targetRegion() {
        return this.budgetHeader?.region || 'GMNA';
    }

    get targetPlant() {
        return this.budgetHeader?.plantName || '—';
    }

    get targetSector() {
        return this.budgetHeader?.sector || this.selectedSector || '—';
    }

    get targetMSchedule() {
        return this.budgetHeader?.mScheduleVersion || this.selectedVersion || '—';
    }

    get targetStatus() {
        return this.budgetHeader?.status || '';
    }

    handleAdjustmentStatusChange(event) {
        const nextStatus = event.detail?.status;
        if (!nextStatus || !this.budgetHeader) {
            return;
        }

        this.budgetHeader = {
            ...this.budgetHeader,
            status: nextStatus
        };
    }

    @wire(getMScheduleOptions)
    wiredMScheduleOptions({ data, error }) {
        if (data) {
            this.mScheduleOptions = data;
        } else if (error) {
            this.mScheduleOptions = [];
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading M-Schedule values',
                    message: error.body?.message || 'Unable to load M-Schedule values.',
                    variant: 'error'
                })
            );
        }
    }

    get summaryCurrentYearLabel() {
        return String(this.budgetHeader?.year || this.selectedYear || '');
    }

    get summaryPreviousYearLabel() {
        const currentYear = Number(this.summaryCurrentYearLabel);
        return Number.isFinite(currentYear) ? String(currentYear - 1) : '';
    }

    get totalManpowerMonthlyValues() {
        const totalOts = this.findRow(this.driverRows, 'total-ots');
        const totalSkilled = this.findRow(this.driverRows, 'total-skilled');
        const totalSalaried = this.findRow(this.driverRows, 'total-salaried');
        const values = {};

        MONTH_COLUMNS.forEach((column) => {
            values[column.key] =
                (Number(totalOts?.values?.[column.key]) || 0) +
                (Number(totalSkilled?.values?.[column.key]) || 0) +
                (Number(totalSalaried?.values?.[column.key]) || 0);
        });

        return values;
    }

    get productivityPercent() {
        const priorYearTotalManpower = Number(this.totalManpowerMonthlyValues.prevDec) || 0;
        const productivityAdjustmentTotal = [
            'prod-ots', 'prod-skilled', 'prod-salaried',
            'mbc-ots', 'mbc-skilled', 'mbc-salaried',
            'lms-ots', 'lms-skilled', 'lms-salaried'
        ].reduce((total, key) => {
            const row = this.findRow(this.driverRows, key);
            return total + (row ? sumMonths(row.values) : 0);
        }, 0);

        return priorYearTotalManpower === 0 ? 0 : (productivityAdjustmentTotal / priorYearTotalManpower) * 100;
    }

    get productivitySummaryPct() {
        return this.productivityPercent;
    }

    get summaryHeroCards() {
        return [
            {
                key: 'pyeHeadcount',
                label: 'PYE Headcount',
                year: this.summaryPreviousYearLabel,
                value: formatValue(this.totalManpowerMonthlyValues.prevDec, 'number'),
                formulaText: getFormulaTextByKey('pyeHeadcount'),
                className: 'summary-total-card'
            },
            {
                key: 'cyeHeadcount',
                label: 'CYE Headcount',
                year: this.summaryCurrentYearLabel,
                value: formatValue(this.totalManpowerMonthlyValues.dec, 'number'),
                formulaText: getFormulaTextByKey('cyeHeadcount'),
                className: 'summary-total-card'
            },
            {
                key: 'cyAveHeadcount',
                label: 'CY Ave. Headcount',
                year: this.summaryCurrentYearLabel,
                value: formatValue(averageMonths(this.totalManpowerMonthlyValues), 'number'),
                formulaText: getFormulaTextByKey('cyAveHeadcount'),
                className: 'summary-total-card'
            },
            {
                key: 'cyProductivity',
                label: 'CY % Productivity',
                year: this.summaryCurrentYearLabel,
                value: formatValue(round(this.productivitySummaryPct, 1), 'percent'),
                formulaText: getFormulaTextByKey('prodPct'),
                className: this.productivitySummaryPct < 0 ? 'summary-total-card summary-total-card_alert' : 'summary-total-card'
            }
        ];
    }

    get summaryOpPlanRows() {
        const rows = [
            this.buildSummaryMetricRow('Crews', this.findRow(this.nonDriverRows, 'crews')?.values, 'number', 'dec', 'YE = December value. CY Average = Jan-Dec average.'),
            this.buildSummaryMetricRow('Shifts', this.findRow(this.nonDriverRows, 'shifts')?.values, 'number', 'dec', 'YE = December value. CY Average = Jan-Dec average.'),
            this.buildSummaryMetricRow('Net/Net JPH', this.findRow(this.nonDriverRows, 'netJph')?.values, 'decimal', 'dec', 'YE = December value. CY Average = Jan-Dec average.'),
            this.buildSummaryMetricRow('Production Days', this.findRow(this.nonDriverRows, 'productionDays')?.values, 'decimal', 'dec', 'YE = December value. CY Average = Jan-Dec average.'),
            this.buildSummaryMetricRow('EQ SOT Days', this.findRow(this.nonDriverRows, 'eqSotDays')?.values, 'decimal', 'dec', 'YE = December value. CY Average = Jan-Dec average.'),
            this.buildSummaryMetricRow('Scheduled Volume', this.findRow(this.nonDriverRows, 'scheduledVolume')?.values, 'number', 'sum', getFormulaTextByKey('summaryOpPlan'))
        ].filter((row) => !!row);

        const stampingStrokes = this.findRow(this.nonDriverRows, 'stampingScheduledVolumeStrokes');
        if (stampingStrokes) {
            rows.push(this.buildSummaryMetricRow('Stamping Strokes', stampingStrokes.values, 'number', 'sum', getFormulaTextByKey('summaryOpPlan')));
        }

        return rows;
    }

    get summaryHoursRows() {
        const allSt = this.sumCalculatedHours('OTS', 'stHours') + this.sumCalculatedHours('Skilled', 'stHours') + this.sumCalculatedHours('Salaried', 'stHours');
        const allSot = this.sumCalculatedHours('OTS', 'scheduledOvertime') + this.sumCalculatedHours('Skilled', 'scheduledOvertime') + this.sumCalculatedHours('Salaried', 'scheduledOvertime');
        const allNsot = this.sumCalculatedHours('OTS', 'nsotHours') + this.sumCalculatedHours('Skilled', 'nsotHours') + this.sumCalculatedHours('Salaried', 'nsotHours');
        const allTotal = this.sumCalculatedHours('OTS', 'totalHours') + this.sumCalculatedHours('Skilled', 'totalHours') + this.sumCalculatedHours('Salaried', 'totalHours');
        const nsotPctValues = { prevDec: null };

        MONTH_COLUMNS
            .filter((column) => column.key !== 'prevDec')
            .forEach((column) => {
                const totalSt = ['OTS', 'Skilled', 'Salaried'].reduce(
                    (sum, classification) => sum + (this.calculateHoursForMonth(classification, column.key).stHours || 0),
                    0
                );
                const totalSot = ['OTS', 'Skilled', 'Salaried'].reduce(
                    (sum, classification) => sum + (this.calculateHoursForMonth(classification, column.key).scheduledOvertime || 0),
                    0
                );
                const totalNsot = ['OTS', 'Skilled', 'Salaried'].reduce(
                    (sum, classification) => sum + (this.calculateHoursForMonth(classification, column.key).nsotHours || 0),
                    0
                );
                nsotPctValues[column.key] = totalSt + totalSot === 0 ? 0 : (totalNsot / (totalSt + totalSot)) * 100;
            });

        return [
            this.buildSummaryValueRow('ST', allSt, 'decimal', 'sum', getFormulaTextByKey('stHours')),
            this.buildSummaryValueRow('SOT', allSot, 'decimal', 'sum', getFormulaTextByKey('scheduledOvertime')),
            this.buildSummaryValueRow('NSOT', allNsot, 'decimal', 'sum', getFormulaTextByKey('nsotHours')),
            this.buildSummaryMetricRow('%NSOT', nsotPctValues, 'percent', 'avg', getFormulaTextByKey('nsotCyPct')),
            this.buildSummaryValueRow('Total Hours', allTotal, 'decimal', 'sum', getFormulaTextByKey('totalHours'))
        ];
    }

    get summaryHeadcountRows() {
        const baseValues = this.buildCombinedDriverValues(['base-ots', 'base-skilled', 'base-salaried']);
        const approvedValues = this.buildCombinedDriverValues(['approved-ots', 'approved-skilled', 'approved-salaried']);
        const productivityValues = this.buildCombinedDriverValues([
            'prod-ots', 'prod-skilled', 'prod-salaried',
            'mbc-ots', 'mbc-skilled', 'mbc-salaried',
            'lms-ots', 'lms-skilled', 'lms-salaried'
        ]);
        const opPlanValues = this.buildCombinedDriverValues(['opplan-ots', 'opplan-skilled', 'opplan-salaried']);
        const vacationValues = this.buildCombinedDriverValues(['vac-ots', 'vac-skilled', 'vac-salaried']);
        const contentValues = this.buildCombinedDriverValues(['content-ots', 'content-skilled', 'content-salaried']);
        const sourcingValues = this.buildCombinedDriverValues(['sourcing-ots', 'sourcing-skilled', 'sourcing-salaried']);
        const othersValues = this.buildCombinedDriverValues(['others-ots', 'others-skilled', 'others-salaried']);
        const mfgOpValues = this.buildCombinedDriverValues(['mfgopt-ots', 'mfgopt-skilled', 'mfgopt-salaried']);

        return [
            this.buildSummaryMetricRow('YE Target', baseValues, 'number', 'prevDec', getSummaryHeadcountFormulaText('YE Target')),
            this.buildSummaryMetricRow('Productivity (all in)', productivityValues, 'number', 'dec', getSummaryHeadcountFormulaText('Productivity (all in)')),
            this.buildSummaryMetricRow('Op Plan Changes', opPlanValues, 'number', 'dec', getSummaryHeadcountFormulaText('Op Plan Changes')),
            this.buildSummaryMetricRow('Vacation Coverage', vacationValues, 'number', 'dec', getSummaryHeadcountFormulaText('Vacation Coverage')),
            this.buildSummaryMetricRow('Content Changes', contentValues, 'number', 'dec', getSummaryHeadcountFormulaText('Content Changes')),
            this.buildSummaryMetricRow('Sourcing', sourcingValues, 'number', 'dec', getSummaryHeadcountFormulaText('Sourcing')),
            this.buildSummaryMetricRow('Others', othersValues, 'number', 'dec', getSummaryHeadcountFormulaText('Others')),
            this.buildSummaryMetricRow('Mfg Op', mfgOpValues, 'number', 'dec', getSummaryHeadcountFormulaText('Mfg Op')),
            this.buildSummaryMetricRow('YE Total', this.totalManpowerMonthlyValues, 'number', 'dec', getSummaryHeadcountFormulaText('YE Total')),
            this.buildSummaryMetricRow('CY Ave.', this.totalManpowerMonthlyValues, 'number', 'avg', getSummaryHeadcountFormulaText('CY Ave.')),
            this.buildSummaryPercentRow('% Prod.', this.productivitySummaryPct, getFormulaTextByKey('prodPct'))
        ];
    }

    get kpiTiles() {
        const calculatedVolume = this.findRow(this.nonDriverRows, 'calcVolume');
        const scheduledVolume = this.findRow(this.nonDriverRows, 'scheduledVolume');
        const volumeVariance = this.findRow(this.nonDriverRows, 'volumeVariance');
        const availableDays = this.findRow(this.nonDriverRows, 'availableDays');
        const productionDays = this.findRow(this.nonDriverRows, 'productionDays');
        const eqSotDays = this.findRow(this.nonDriverRows, 'eqSotDays');
        const stampingSotEquivalentDaysTotal = this.findRow(this.nonDriverRows, 'stampingSotEquivalentDaysTotal');

        const yearCalculated = sumMonths(calculatedVolume.values);
        const yearScheduled = sumMonths(scheduledVolume.values);
        const yearVariance = sumMonths(volumeVariance.values);
        const variancePct = yearScheduled === 0 ? 0 : (yearVariance / yearScheduled) * 100;

        const equivalentDaysTile = this.isStampingSector
            ? {
                key: 'stampingSotEquivalentDaysTotal',
                label: 'SOT equivalent days total',
                value: formatValue(sumMonths(stampingSotEquivalentDaysTotal?.values || ZERO_MONTH_VALUES), 'decimal'),
                formulaText: getFormulaTextByKey('stampingSotEquivalentDaysTotal'),
                className: 'kpi-card'
            }
            : {
                key: 'eqSotDays',
                label: 'EQ SOT Days',
                value: formatValue(sumMonths(eqSotDays.values), 'decimal'),
                formulaText: 'Year total = Jan-Dec sum of EQ SOT Days.',
                className: 'kpi-card'
            };

        return [
            { key: 'calcVolume', label: 'Calculated Volume incl. SOT days', value: formatValue(yearCalculated, 'number'), formulaText: getFormulaTextByKey('calcVolume'), className: 'kpi-card' },
            { key: 'scheduledVolume', label: 'Scheduled Volume', value: formatValue(yearScheduled, 'number'), formulaText: getFormulaTextByKey('scheduledVolume'), className: 'kpi-card' },
            { key: 'volumeVariance', label: 'Scheduled Volume minus Calculated Volume', value: formatValue(yearVariance, 'number'), formulaText: getFormulaTextByKey('volumeVariance'), className: 'kpi-card' },
            { key: 'variancePct', label: 'Scheduled Volume Variance', value: formatValue(round(variancePct, 1), 'percent'), formulaText: 'Scheduled Volume Variance = (Scheduled Volume minus Calculated Volume) / Scheduled Volume', className: variancePct < 0 ? 'kpi-card kpi-card_alert' : 'kpi-card' },
            { key: 'availableDays', label: 'Available Working Days / Month', value: formatValue(sumMonths(availableDays.values), 'decimal'), formulaText: 'Year total = Jan-Dec sum of Available Working Days / Month.', className: 'kpi-card' },
            { key: 'productionDays', label: 'Production Working Days / Month', value: formatValue(sumMonths(productionDays.values), 'decimal'), formulaText: 'Year total = Jan-Dec sum of Production Working Days / Month.', className: 'kpi-card' },
            equivalentDaysTile
        ];
    }

    get manpowerKpiTiles() {
        const totalOts = this.findRow(this.driverRows, 'total-ots');
        const totalSkilled = this.findRow(this.driverRows, 'total-skilled');
        const totalSalaried = this.findRow(this.driverRows, 'total-salaried');

        const totalByMonth = {};
        MONTH_COLUMNS.filter((column) => column.key !== 'prevDec').forEach((column) => {
            totalByMonth[column.key] =
                (Number(totalOts.values[column.key]) || 0) +
                (Number(totalSkilled.values[column.key]) || 0) +
                (Number(totalSalaried.values[column.key]) || 0);
        });

        const prodPct = this.productivityPercent;

        return [
            { key: 'prodPct', label: 'Productivity %', value: formatValue(round(prodPct, 1), 'percent'), formulaText: getFormulaTextByKey('prodPct'), className: prodPct < 0 ? 'kpi-card kpi-card_alert' : 'kpi-card' },
            { key: 'averageTotal', label: 'Average Total', value: formatValue(averageMonths(totalByMonth), 'number'), formulaText: getFormulaTextByKey('averageTotal'), className: 'kpi-card' }
        ];
    }

    get hoursKpiTiles() {
        const allSt =
            this.sumCalculatedHours('OTS', 'stHours') +
            this.sumCalculatedHours('Skilled', 'stHours') +
            this.sumCalculatedHours('Salaried', 'stHours');
        const allNsot =
            this.sumCalculatedHours('OTS', 'nsotHours') +
            this.sumCalculatedHours('Skilled', 'nsotHours') +
            this.sumCalculatedHours('Salaried', 'nsotHours');
        const allSot =
            this.sumCalculatedHours('OTS', 'scheduledOvertime') +
            this.sumCalculatedHours('Skilled', 'scheduledOvertime') +
            this.sumCalculatedHours('Salaried', 'scheduledOvertime');
        const allAdditionalStraightTime =
            this.sumCalculatedHours('OTS', 'additionalStraightTime') +
            this.sumCalculatedHours('Skilled', 'additionalStraightTime') +
            this.sumCalculatedHours('Salaried', 'additionalStraightTime');
        const allTotalHours =
            this.sumCalculatedHours('OTS', 'totalHours') +
            this.sumCalculatedHours('Skilled', 'totalHours') +
            this.sumCalculatedHours('Salaried', 'totalHours');
        const nsotCyPct = allSt + allSot === 0 ? 0 : (allNsot / (allSt + allSot)) * 100;
        const sotCyPct = allSt === 0 ? 0 : (allSot / allSt) * 100;

        return [
            { key: 'stHours', label: "ST Hours (inc. Add'l ST Hours)", value: formatValue(round(allSt, 1), 'decimal'), formulaText: getFormulaTextByKey('stHoursTile'), className: 'kpi-card' },
            { key: 'nsotHours', label: 'NSOT Hours', value: formatValue(round(allNsot, 1), 'decimal'), formulaText: getFormulaTextByKey('nsotHoursTile'), className: 'kpi-card' },
            { key: 'nsotCyPct', label: 'NSOT CY %', value: formatValue(round(nsotCyPct, 1), 'percent'), formulaText: getFormulaTextByKey('nsotCyPct'), className: 'kpi-card' },
            { key: 'sotCyPct', label: 'SOT CY %', value: formatValue(round(sotCyPct, 1), 'percent'), formulaText: getFormulaTextByKey('sotCyPct'), className: 'kpi-card' },
            { key: 'additionalSt', label: 'Additional ST Hours', value: formatValue(round(allAdditionalStraightTime, 1), 'decimal'), formulaText: getFormulaTextByKey('additionalSt'), className: 'kpi-card' },
            { key: 'totalHours', label: 'Total Hours', value: formatValue(round(allTotalHours, 1), 'decimal'), formulaText: getFormulaTextByKey('totalHoursTile'), className: 'kpi-card' }
        ];
    }

    get summaryBlocks() {
        const scheduledVolume = this.findRow(this.nonDriverRows, 'scheduledVolume');
        const calculatedVolume = this.findRow(this.nonDriverRows, 'calcVolume');
        const volumeVariance = this.findRow(this.nonDriverRows, 'volumeVariance');
        const availableDays = this.findRow(this.nonDriverRows, 'availableDays');
        const productionDays = this.findRow(this.nonDriverRows, 'productionDays');
        const eqSotDays = this.findRow(this.nonDriverRows, 'eqSotDays');
        const crews = this.findRow(this.nonDriverRows, 'crews');
        const shifts = this.findRow(this.nonDriverRows, 'shifts');
        const netJph = this.findRow(this.nonDriverRows, 'netJph');
        const totalOts = this.findRow(this.driverRows, 'total-ots');
        const totalSkilled = this.findRow(this.driverRows, 'total-skilled');
        const totalSalaried = this.findRow(this.driverRows, 'total-salaried');

        const yearScheduled = sumMonths(scheduledVolume.values);
        const yearCalculated = sumMonths(calculatedVolume.values);
        const yearVariance = sumMonths(volumeVariance.values);
        const scheduledVariancePct = yearScheduled === 0 ? 0 : (yearVariance / yearScheduled) * 100;
        const yearPaidHours = sumMonths(this.findRow(this.nonDriverRows, 'paidHoursPerCrew').values);
        const yearAvailableDays = sumMonths(availableDays.values);
        const yearProductionDays = sumMonths(productionDays.values);
        const yearEqSotDays = sumMonths(eqSotDays.values);
        const allStHours =
            this.sumCalculatedHours('OTS', 'stHours') +
            this.sumCalculatedHours('Skilled', 'stHours') +
            this.sumCalculatedHours('Salaried', 'stHours');
        const allNsotHours =
            this.sumCalculatedHours('OTS', 'nsotHours') +
            this.sumCalculatedHours('Skilled', 'nsotHours') +
            this.sumCalculatedHours('Salaried', 'nsotHours');
        const allScheduledOvertime =
            this.sumCalculatedHours('OTS', 'scheduledOvertime') +
            this.sumCalculatedHours('Skilled', 'scheduledOvertime') +
            this.sumCalculatedHours('Salaried', 'scheduledOvertime');
        const allAdditionalStraightTime =
            this.sumCalculatedHours('OTS', 'additionalStraightTime') +
            this.sumCalculatedHours('Skilled', 'additionalStraightTime') +
            this.sumCalculatedHours('Salaried', 'additionalStraightTime');
        const allTotalHours =
            this.sumCalculatedHours('OTS', 'totalHours') +
            this.sumCalculatedHours('Skilled', 'totalHours') +
            this.sumCalculatedHours('Salaried', 'totalHours');
        const otsTotalHours = this.sumCalculatedHours('OTS', 'totalHours');
        const skilledTotalHours = this.sumCalculatedHours('Skilled', 'totalHours');
        const salariedTotalHours = this.sumCalculatedHours('Salaried', 'totalHours');
        const nsotCyPct = allStHours + allScheduledOvertime === 0 ? 0 : (allNsotHours / (allStHours + allScheduledOvertime)) * 100;
        const sotCyPct = allStHours === 0 ? 0 : (allScheduledOvertime / allStHours) * 100;
        const priorYearTotalManpower = (Number(totalOts.values.prevDec) || 0) + (Number(totalSkilled.values.prevDec) || 0) + (Number(totalSalaried.values.prevDec) || 0);
        const prodDriverTotal =
            ['prod-ots', 'prod-skilled', 'prod-salaried', 'mbc-ots', 'mbc-skilled', 'mbc-salaried', 'lms-ots', 'lms-skilled', 'lms-salaried']
                .reduce((total, key) => total + sumMonths(this.findRow(this.driverRows, key).values), 0);
        const prodPct = priorYearTotalManpower === 0 ? 0 : (prodDriverTotal / priorYearTotalManpower) * 100;
        const averageHeadcount = averageMonths({
            jan: (Number(totalOts.values.jan) || 0) + (Number(totalSkilled.values.jan) || 0) + (Number(totalSalaried.values.jan) || 0),
            feb: (Number(totalOts.values.feb) || 0) + (Number(totalSkilled.values.feb) || 0) + (Number(totalSalaried.values.feb) || 0),
            mar: (Number(totalOts.values.mar) || 0) + (Number(totalSkilled.values.mar) || 0) + (Number(totalSalaried.values.mar) || 0),
            apr: (Number(totalOts.values.apr) || 0) + (Number(totalSkilled.values.apr) || 0) + (Number(totalSalaried.values.apr) || 0),
            may: (Number(totalOts.values.may) || 0) + (Number(totalSkilled.values.may) || 0) + (Number(totalSalaried.values.may) || 0),
            jun: (Number(totalOts.values.jun) || 0) + (Number(totalSkilled.values.jun) || 0) + (Number(totalSalaried.values.jun) || 0),
            jul: (Number(totalOts.values.jul) || 0) + (Number(totalSkilled.values.jul) || 0) + (Number(totalSalaried.values.jul) || 0),
            aug: (Number(totalOts.values.aug) || 0) + (Number(totalSkilled.values.aug) || 0) + (Number(totalSalaried.values.aug) || 0),
            sep: (Number(totalOts.values.sep) || 0) + (Number(totalSkilled.values.sep) || 0) + (Number(totalSalaried.values.sep) || 0),
            oct: (Number(totalOts.values.oct) || 0) + (Number(totalSkilled.values.oct) || 0) + (Number(totalSalaried.values.oct) || 0),
            nov: (Number(totalOts.values.nov) || 0) + (Number(totalSkilled.values.nov) || 0) + (Number(totalSalaried.values.nov) || 0),
            dec: (Number(totalOts.values.dec) || 0) + (Number(totalSkilled.values.dec) || 0) + (Number(totalSalaried.values.dec) || 0)
        });

        const driverAverageRows = this.driverRows
            .filter((row) => !row.key.startsWith('total-'))
            .map((row) => ({
                key: `driver-avg-${row.key}`,
                metric: `${row.driver} (${row.classification})`,
                current: formatValue(averageMonths(row.values), row.valueType),
                delta: '—',
                variance: 'Avg'
            }));

        return [
            {
                key: 'yearTotals',
                kicker: 'Year Totals',
                title: 'Budget Year Totals',
                highlight: `${formatValue(allTotalHours, 'decimal')} hrs`,
                rows: [
                    { key: 'scheduled', metric: 'Scheduled Volume', current: formatValue(yearScheduled, 'number'), delta: '—', variance: 'Total' },
                    { key: 'calculated', metric: 'Calculated Volume incl. SOT days', current: formatValue(yearCalculated, 'number'), delta: '—', variance: 'Total' },
                    { key: 'variance', metric: 'Scheduled Volume minus Calculated Volume', current: formatValue(yearVariance, 'number'), delta: '—', variance: 'Total' },
                    { key: 'variancePct', metric: 'Scheduled Volume Variance', current: formatValue(round(scheduledVariancePct, 1), 'percent'), delta: '—', variance: '%' },
                    { key: 'paidHours', metric: 'Paid Hours Per CREW', current: formatValue(yearPaidHours, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'availableDays', metric: 'Available Working Days / Month', current: formatValue(yearAvailableDays, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'productionDays', metric: 'Production Working Days / Month', current: formatValue(yearProductionDays, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'eqSotDays', metric: 'EQ SOT Days', current: formatValue(yearEqSotDays, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'stHours', metric: "ST Hours (inc. Add'l ST Hours)", current: formatValue(allStHours, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'nsotHours', metric: 'NSOT Hours', current: formatValue(allNsotHours, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'sotHours', metric: 'Scheduled Overtime Hours', current: formatValue(allScheduledOvertime, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'astHours', metric: "Additional Straight Time Hours", current: formatValue(allAdditionalStraightTime, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'totalHoursOts', metric: 'Total Hours (OTS)', current: formatValue(otsTotalHours, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'totalHoursSkilled', metric: 'Total Hours (Skilled)', current: formatValue(skilledTotalHours, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'totalHoursSalaried', metric: 'Total Hours (Salaried)', current: formatValue(salariedTotalHours, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'totalHoursAll', metric: 'Total Hours (All)', current: formatValue(allTotalHours, 'decimal'), delta: '—', variance: 'Total' },
                    { key: 'nsotCy', metric: 'NSOT CY Percent', current: formatValue(round(nsotCyPct, 1), 'percent'), delta: '—', variance: '%' },
                    { key: 'sotCy', metric: 'SOT CY Percent', current: formatValue(round(sotCyPct, 1), 'percent'), delta: '—', variance: '%' },
                    { key: 'prodPct', metric: '% Prod', current: formatValue(round(prodPct, 1), 'percent'), delta: '—', variance: '%' }
                ]
            },
            {
                key: 'yearAverages',
                kicker: 'Year Averages',
                title: 'Driver and Manpower Averages',
                highlight: `${formatValue(averageHeadcount, 'number')} avg HC`,
                rows: [
                    { key: 'avg-ots', metric: 'Total Manpower (OTS)', current: formatValue(averageMonths(totalOts.values), 'number'), delta: '—', variance: 'Avg' },
                    { key: 'avg-skilled', metric: 'Total Manpower (Skilled)', current: formatValue(averageMonths(totalSkilled.values), 'number'), delta: '—', variance: 'Avg' },
                    { key: 'avg-salaried', metric: 'Total Manpower (Salaried)', current: formatValue(averageMonths(totalSalaried.values), 'number'), delta: '—', variance: 'Avg' },
                    { key: 'avg-total', metric: 'Total Manpower (All)', current: formatValue(averageHeadcount, 'number'), delta: '—', variance: 'Avg' },
                    ...driverAverageRows
                ]
            }
        ].map((block) => ({
            ...block,
            rows: block.rows
                .filter((row) => rowMatchesQuickFilter(row, this.selectedQuickFilter))
                .map((row) => ({
                    ...row,
                    rowClass: rowMatchesPinnedKpi(row, this.selectedPinnedKpi) ? 'summary-row summary-row_highlight' : 'summary-row'
                }))
        }));
    }

    get comparisonBlocks() {
        const base = this.summaryBlocks;

        return base.map((block, index) => ({
            ...block,
            key: `${block.key}-comparison`,
            kicker: index === 0 ? 'Summary with Comparison' : 'Prior Target Comparison',
            rows: block.rows.map((row) => ({
                ...row,
                compare: row.current,
                target: index === 0 ? row.delta : row.variance,
                targetClass: String(index === 0 ? row.delta : row.variance).includes('-') ? 'metric-pill metric-pill_alert' : 'metric-pill'
            }))
        }));
    }

    buildCombinedDriverValues(rowKeys) {
        const values = {};
        MONTH_COLUMNS.forEach((column) => {
            values[column.key] = 0;
        });

        (rowKeys || []).forEach((rowKey) => {
            const row = this.findRow(this.driverRows, rowKey);
            if (!row) {
                return;
            }
            MONTH_COLUMNS.forEach((column) => {
                values[column.key] += Number(row.values?.[column.key]) || 0;
            });
        });

        return values;
    }

    getSummaryPeriodValue(values, mode) {
        if (!values) {
            return 0;
        }
        if (mode === 'prevDec') {
            return Number(values.prevDec) || 0;
        }
        if (mode === 'avg') {
            return averageMonths(values);
        }
        if (mode === 'sum') {
            return sumMonths(values);
        }
        return Number(values.dec) || 0;
    }

    buildSummaryMetricRow(label, values, valueType, yearMode = 'dec', formulaText = '') {
        if (!values) {
            return null;
        }

        return {
            key: `summary-${label.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`,
            label,
            formulaText,
            yearEnd: formatValue(this.getSummaryPeriodValue(values, yearMode), valueType),
            average: formatValue(averageMonths(values), valueType)
        };
    }

    buildSummaryValueRow(label, value, valueType, mode = 'sum', formulaText = '') {
        const numericValue = Number(value) || 0;
        const averageValue = mode === 'sum' ? round(numericValue / 12, 1) : numericValue;

        return {
            key: `summary-${label.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`,
            label,
            formulaText,
            yearEnd: formatValue(numericValue, valueType),
            average: formatValue(averageValue, valueType)
        };
    }

    buildSummaryPercentRow(label, value, formulaText = '') {
        const percentValue = Number(value) || 0;
        return {
            key: `summary-${label.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`,
            label,
            formulaText,
            yearEnd: formatValue(round(percentValue, 1), 'percent'),
            average: formatValue(round(percentValue, 1), 'percent')
        };
    }

    get filterColumns() {
        return [
            {
                key: 'drivers',
                title: 'Driver Defaults',
                items: [
                    this.buildFilterItem('drivers', 'absenteeism', 'Absenteeism %', this.selectedDriverDefault === 'absenteeism'),
                    this.buildFilterItem('drivers', 'nsot', 'NSOT %', this.selectedDriverDefault === 'nsot'),
                    this.buildFilterItem('drivers', 'paidHours', 'Paid Hours / Crew', this.selectedDriverDefault === 'paidHours'),
                    this.buildFilterItem('drivers', 'productionDays', 'Production Days', this.selectedDriverDefault === 'productionDays'),
                    this.buildFilterItem('drivers', 'eqSotDays', 'EQ SOT Days', this.selectedDriverDefault === 'eqSotDays')
                ]
            },
            {
                key: 'views',
                title: 'Quick Filters',
                items: [
                    this.buildFilterItem('views', 'assemblyOnly', 'Assembly only', this.selectedQuickFilter === 'assemblyOnly'),
                    this.buildFilterItem('views', 'polymersOnly', 'Polymers only', this.selectedQuickFilter === 'polymersOnly'),
                    this.buildFilterItem('views', 'highVariance', 'High variance rows', this.selectedQuickFilter === 'highVariance'),
                    this.buildFilterItem('views', 'adjustmentsOnly', 'Adjustments only', this.selectedQuickFilter === 'adjustmentsOnly'),
                    this.buildFilterItem('views', 'showCalculated', 'Show calculated', this.selectedQuickFilter === 'showCalculated')
                ]
            },
            {
                key: 'kpis',
                title: 'Pinned KPIs',
                items: [
                    this.buildFilterItem('kpis', 'scheduledVolumeVariance', 'Scheduled Volume Variance', this.selectedPinnedKpi === 'scheduledVolumeVariance'),
                    this.buildFilterItem('kpis', 'prodPct', '% Prod', this.selectedPinnedKpi === 'prodPct'),
                    this.buildFilterItem('kpis', 'averageHc', 'Average HC', this.selectedPinnedKpi === 'averageHc'),
                    this.buildFilterItem('kpis', 'volumeVsPlan', 'Volume vs Plan', this.selectedPinnedKpi === 'volumeVsPlan'),
                    this.buildFilterItem('kpis', 'readyForPublish', 'Ready for Publish', this.selectedPinnedKpi === 'readyForPublish')
                ]
            }
        ];
    }

    handleExpandAll() {
        if (this.isGuidedTableMode) {
            return;
        }
        this.activeSectionNames = ['nonDriver', 'driver', 'hours', 'summary', 'comparison'];
    }

    handleCollapseAll() {
        if (this.isGuidedTableMode) {
            return;
        }
        this.activeSectionNames = [];
    }

    handleViewTabChange(event) {
        const nextTab = event.currentTarget?.dataset?.tab;
        if (!nextTab || nextTab === this.activeViewTab) {
            return;
        }
        if ((nextTab === 'summary' && !this.showSummaryTab) || (nextTab === 'adjustments' && !this.showAdjustmentsTab)) {
            return;
        }
        this.activeViewTab = nextTab;
    }

    handleViewModeToggle(event) {
        const nextMode = !!event.target.checked;
        this.isGuidedTableMode = nextMode;

        if (nextMode) {
            this.accordionSectionNamesSnapshot = [...this.activeSectionNames];
            const firstOpenSection = SECTION_ORDER.findIndex((name) => this.activeSectionNames.includes(name));
            this.guidedSectionIndex = firstOpenSection >= 0 ? firstOpenSection : 0;
            this.activeSectionNames = [this.guidedCurrentSectionName];
            return;
        }

        const restoredSections = this.accordionSectionNamesSnapshot?.length
            ? this.accordionSectionNamesSnapshot
            : OPEN_SECTIONS;
        this.activeSectionNames = [...new Set(restoredSections)];
    }

    handleGuidedNext() {
        if (this.disableGuidedNext) {
            return;
        }
        this.guidedSectionIndex += 1;
        this.activeSectionNames = [this.guidedCurrentSectionName];
    }

    handleGuidedPrevious() {
        if (this.disableGuidedPrevious) {
            return;
        }
        this.guidedSectionIndex -= 1;
        this.activeSectionNames = [this.guidedCurrentSectionName];
    }

    handleFilterClick(event) {
        const group = event.currentTarget.dataset.group;
        const value = event.currentTarget.dataset.value;

        if (group === 'views') {
            this.selectedQuickFilter = this.selectedQuickFilter === value ? '' : value;

            if (this.selectedQuickFilter === 'assemblyOnly') {
                this.selectedScope = 'Assembly only';
            } else if (this.selectedQuickFilter === 'polymersOnly') {
                this.selectedScope = 'Polymers only';
            } else {
                this.selectedScope = 'Assembly / Polymers';
            }

            this.activeSectionNames = [...new Set([...this.activeSectionNames, 'summary', 'comparison'])];
            return;
        }

        if (group === 'drivers') {
            this.selectedDriverDefault = this.selectedDriverDefault === value ? '' : value;
            this.activeSectionNames = [...new Set([...this.activeSectionNames, 'nonDriver', 'driver', 'hours'])];
            return;
        }

        this.selectedPinnedKpi = this.selectedPinnedKpi === value ? '' : value;
        this.activeSectionNames = [...new Set([...this.activeSectionNames, 'summary', 'comparison'])];
    }

    handleSectionToggle(event) {
        const sectionName = event.currentTarget.dataset.name;
        if (!sectionName) {
            return;
        }

        if (this.isGuidedTableMode) {
            const sectionIndex = SECTION_ORDER.indexOf(sectionName);
            if (sectionIndex >= 0) {
                this.guidedSectionIndex = sectionIndex;
                this.activeSectionNames = [sectionName];
            }
            return;
        }

        if (this.activeSectionNames.includes(sectionName)) {
            this.activeSectionNames = this.activeSectionNames.filter((name) => name !== sectionName);
            return;
        }

        this.activeSectionNames = [...this.activeSectionNames, sectionName];
    }

    handleCellChange(event) {
        const tableName = event.target.dataset.table;
        const rowKey = event.target.dataset.rowKey;
        const monthKey = event.target.dataset.monthKey;
        const valueType = this.getCellValueType(tableName, rowKey);
        const rawValue = this.sanitizeDraftInputValue(event.target.value, valueType);
        const cellKey = this.getGridCellKey(tableName, rowKey, monthKey);

        if (event.target.value !== rawValue) {
            event.target.value = rawValue;
        }

        if (event.type === 'input') {
            this.setDraftCellValue(cellKey, rawValue);
            return;
        }

        this.clearDraftCellValue(cellKey);
        const value = this.normalizeCellInputValue(rawValue, event.type, valueType);
        if (value === null) {
            return;
        }
        this.applyCellValueChange(tableName, rowKey, monthKey, value);
    }

    syncVisibleInputsToState() {
        const visibleInputs = [...this.template.querySelectorAll('input.grid-input')];
        if (!visibleInputs.length) {
            return;
        }

        const groupedValues = new Map();

        visibleInputs.forEach((inputToSync) => {
            const tableName = inputToSync.dataset.table;
            const rowKey = inputToSync.dataset.rowKey;
            const monthKey = inputToSync.dataset.monthKey;
            if (!tableName || !rowKey || !monthKey) {
                return;
            }

            const value = this.normalizeCellInputValue(
                this.sanitizeDraftInputValue(inputToSync.value, this.getCellValueType(tableName, rowKey)),
                'change',
                this.getCellValueType(tableName, rowKey)
            );
            if (value === null) {
                return;
            }

            const groupKey = `${tableName}:${rowKey}`;
            if (!groupedValues.has(groupKey)) {
                groupedValues.set(groupKey, {
                    tableName,
                    rowKey,
                    values: {}
                });
            }

            groupedValues.get(groupKey).values[monthKey] = value;
        });

        groupedValues.forEach((group) => {
            const sourceRows = group.tableName === 'driver' ? this.driverRows : this.nonDriverRows;
            const existingRow = this.findRow(sourceRows, group.rowKey);
            if (!existingRow) {
                return;
            }

            const nextValues = {
                ...existingRow.values,
                ...group.values
            };

            if (group.tableName === 'driver') {
                this.driverRows = this.driverRows.map((row) => (row.key === group.rowKey ? { ...row, values: nextValues } : row));
            } else {
                this.nonDriverRows = this.nonDriverRows.map((row) => (row.key === group.rowKey ? { ...row, values: nextValues } : row));
            }

            this.debugLog('syncVisibleInputsToState row snapshot', {
                tableName: group.tableName,
                rowKey: group.rowKey,
                values: nextValues
            });
        });

        this.recalculateNonDriver();
        this.recalculateDriverTotals();
    }

    normalizeCellInputValue(rawValue, eventType = 'change', valueType = 'number') {
        const normalized = String(rawValue ?? '').trim();
        const isInputEvent = eventType === 'input';
        if (isInputEvent && ['-', '+', '.', '-.', '+.'].includes(normalized)) {
            // Allow intermediate typing states for signed/decimal entry.
            return null;
        }
        if (normalized === '') {
            return 0;
        }

        const parsedValue = Number(normalized);
        if (Number.isNaN(parsedValue)) {
            return isInputEvent ? null : 0;
        }
        if (valueType === 'number') {
            return Math.trunc(parsedValue);
        }
        return parsedValue;
    }

    sanitizeDraftInputValue(rawValue, valueType = 'number') {
        const normalized = String(rawValue ?? '');
        if (valueType !== 'number') {
            return normalized;
        }

        if (normalized === '' || normalized === '-' || normalized === '+') {
            return normalized;
        }

        const signedIntegerMatch = normalized.match(/^([+-]?\d*)(?:\.\d*)?$/);
        if (signedIntegerMatch) {
            return signedIntegerMatch[1];
        }

        const fallbackMatch = normalized.match(/[+-]?\d+/);
        return fallbackMatch ? fallbackMatch[0] : '';
    }

    getCellValueType(tableName, rowKey) {
        const sourceRows = tableName === 'driver' ? this.driverRows : this.nonDriverRows;
        return this.findRow(sourceRows, rowKey)?.valueType || 'number';
    }

    applyCellValueChange(tableName, rowKey, monthKey, value) {
        const fillForward = FILL_FORWARD_ROW_KEYS.has(rowKey) && monthKey !== 'prevDec';
        this.dirtyRowKeys.add(rowKey);
        this.markDirtyCellKeys(tableName, rowKey, monthKey, fillForward);

        if (tableName === 'nonDriver') {
            this.nonDriverRows = this.updateRows(this.nonDriverRows, rowKey, monthKey, value, fillForward);
            this.recalculateNonDriver();
            this.recalculateDriverTotals();
            this.selectCommentCell(tableName, rowKey, monthKey);
            return;
        }

        this.driverRows = this.updateRows(this.driverRows, rowKey, monthKey, value, fillForward);
        this.recalculateDriverTotals();
        this.selectCommentCell(tableName, rowKey, monthKey);
    }

    buildRenderRows(rows, tableName) {
        const latestCellKey = this.latestCommentCellKey;
        return rows.map((row, index) => ({
            key: row.key,
            rowNumber: index + 1,
            category: row.category || '',
            driver: row.driver,
            classification: row.classification,
            valueType: row.valueType,
            values: row.values,
            isGroupParent: !!row.isGroupParent,
            isGroupChild: !!row.isGroupChild,
            groupKey: row.groupKey || null,
            groupExpanded: !!row.groupExpanded,
            groupIconClass: row.groupExpanded ? 'row-toggle__icon row-toggle__icon_open' : 'row-toggle__icon',
            driverClass: row.isGroupChild ? 'row-header__child' : '',
            formulaText: getFormulaTextByKey(row.formulaKey || getBaseFormulaKey(row.key)),
            isJustificationDisplayRow: !!row.isJustificationDisplayRow,
            justificationText: row.justificationText || '',
            justificationColSpan: row.justificationColSpan || MONTH_COLUMNS.length + 1,
            showJustificationButton: !!row.showJustificationButton,
            justificationTableName: row.justificationTableName || '',
            justificationRowKey: row.justificationRowKey || '',
            justificationMonthKey: row.justificationMonthKey || '',
            totalClassificationFormulaText: row.classification === 'Total' ? getTotalClassificationHelpText(row) : '',
            yearTotalFormulaText: getYearTotalHelpText(row, tableName),
            rowClass: `${row.editable ? 'grid-row' : 'grid-row grid-row_readonly'} ${this.getClassificationRowClass(row.classification)}`.trim(),
            classificationClass: `cell-classification ${this.getClassificationTextClass(row.classification)}`.trim(),
            summaryValue:
                usesCumulativeAverageHeadcount(row, tableName)
                    ? formatValue(cumulativeAverage(row.values), row.valueType)
                    : summaryValue(row),
            cells: MONTH_COLUMNS.map((column) => {
                const cellTableName = row.tableNameOverride || tableName;
                const isJustificationDisplayRow = row.valueType === 'text';
                const commentRowKey = isJustificationDisplayRow ? row.key : (row.commentSourceRowKey || row.key);
                const hasComments = isJustificationDisplayRow
                    ? false
                    : this.getCellCommentCount(cellTableName, commentRowKey, column.key) > 0;
                const justificationRowKey = getAdditionalStraightJustificationRowKey();
                const justificationCount = ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(row.key) && column.key !== 'prevDec'
                    ? this.getCellCommentCount('hoursJustification', justificationRowKey, column.key)
                    : 0;
                const vacationMarker = getVacationCoverageMarker(this.vacationCoverageConfig, row.key, column.key);
                const isLockedVacationCell =
                    row.key === 'vac-ots' &&
                    !!vacationMarker &&
                    this.hasAssemblyVacationCoverageConfig;
                const cellKey = this.getGridCellKey(cellTableName, commentRowKey, column.key);
                const draftInputValue = this.getDraftCellValue(cellKey);
                // baseEditable reflects the row's natural editability, independent of the
                // Plant Admin lock. Used for both the final editable flag and commentable so
                // that Plant_Admin users retain comment access on read-only input rows.
                const baseEditable = row.editable && column.editable && !this.disableEditing && !isLockedVacationCell;
                // In Plant Review mode, Plant_Admin may only enter values in astadj-* cells.
                const isPlantAdminLocked = this.isPlantAdminReviewMode && !ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(row.key);
                return ({
                key: `${row.key}-${column.key}`,
                monthKey: column.key,
                inputValue:
                    draftInputValue !== undefined
                        ? draftInputValue
                        : (isEmptyMonthValue(row.values[column.key]) || isZeroLikeNumericValue(row.values[column.key]) ? '' : row.values[column.key]),
                inputStep: row.valueType === 'number' ? '1' : '0.1',
                displayValue: formatValue(row.values[column.key], row.valueType),
                editable: baseEditable && !isPlantAdminLocked,
                commentable: baseEditable && !isJustificationDisplayRow,
                tableName: cellTableName,
                rowKey: commentRowKey,
                commentCount: isJustificationDisplayRow ? 0 : this.getCellCommentCount(cellTableName, commentRowKey, column.key),
                hasComments,
                hasSavedComments: hasComments,
                showJustifyButton:
                    ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(row.key) &&
                    column.key !== 'prevDec' &&
                    !!column.editable,
                justificationTableName: 'hoursJustification',
                justificationRowKey,
                justificationMonthKey: column.key,
                justificationButtonLabel: justificationCount > 0 ? 'Edit Reason' : 'Add Reason',
                hasJustification: justificationCount > 0,
                justificationButtonClass: justificationCount > 0 ? 'cell-justify-btn cell-justify-btn_saved' : 'cell-justify-btn',
                vacationMarkerLabel: vacationMarker?.label || '',
                vacationMarkerClass: vacationMarker?.className || '',
                vacationMarkerTooltip: vacationMarker?.tooltip || '',
                showVacationMarker: !!vacationMarker,
                showCommentIndicator:
                    !isJustificationDisplayRow
                        ? (
                            this.getCellCommentCount(cellTableName, commentRowKey, column.key) > 0 ||
                            (
                                baseEditable &&
                                this.isPendingCommentCell(cellTableName, commentRowKey, column.key)
                            )
                        )
                        : false,
                commentIconClass: isJustificationDisplayRow ? '' : this.getCommentIconClass(cellTableName, commentRowKey, column.key),
                cellClass: `${this.getCellClass({
                    columnKey: column.key,
                    editable: row.editable,
                    classification: row.classification,
                    tableName: cellTableName,
                    rowKey: commentRowKey,
                    monthKey: column.key,
                    latestCellKey
                })} ${isJustificationDisplayRow ? 'grid-cell_text-display' : ''}`.trim()
            });
            })
        }));
    }

    getCellClass({ columnKey, editable, classification, tableName, rowKey, monthKey, latestCellKey }) {
        let baseClass = '';
        if (columnKey === 'prevDec') {
            baseClass = 'grid-cell grid-cell_prev';
        } else if (editable) {
            baseClass = `grid-cell ${this.getClassificationCellClass(classification)}`.trim();
        } else {
            baseClass = 'grid-cell grid-cell_calculated';
        }

        const cellKey = `${tableName}:${rowKey}:${monthKey}`;
        const hasSavedComment = this.getCellCommentCount(tableName, rowKey, monthKey) > 0;
        const isPendingComment = this.isPendingCommentCell(tableName, rowKey, monthKey);
        const isSessionComment = this.sessionSavedCommentCellKeys.has(cellKey);
        const isDirtyCell = this.dirtyCellKeys.has(cellKey);

        if (isPendingComment) {
            baseClass = `${baseClass} grid-cell_comment-pending`.trim();
        } else if (isSessionComment) {
            baseClass = `${baseClass} grid-cell_comment-session`.trim();
        } else if (hasSavedComment) {
            baseClass = `${baseClass} grid-cell_comment-existing`.trim();
        }

        if (latestCellKey && latestCellKey === cellKey) {
            baseClass = `${baseClass} grid-cell_latest-activity`.trim();
        }
        if (isDirtyCell) {
            baseClass = `${baseClass} grid-cell_edited`.trim();
        }
        return baseClass;
    }

    markDirtyCellKeys(tableName, rowKey, monthKey, fillForward) {
        const rowTableName = tableName || 'nonDriver';
        this.dirtyCellKeys.add(`${rowTableName}:${rowKey}:${monthKey}`);
        if (!fillForward || monthKey === 'prevDec') {
            return;
        }

        const monthOrder = MONTH_COLUMNS.filter((column) => column.key !== 'prevDec').map((column) => column.key);
        const selectedMonthIndex = monthOrder.indexOf(monthKey);
        if (selectedMonthIndex < 0) {
            return;
        }

        for (let index = selectedMonthIndex + 1; index < monthOrder.length; index += 1) {
            this.dirtyCellKeys.add(`${rowTableName}:${rowKey}:${monthOrder[index]}`);
        }
    }

    getGridCellKey(tableName, rowKey, monthKey) {
        return `${tableName || 'nonDriver'}:${rowKey}:${monthKey}`;
    }

    getDraftCellValue(cellKey) {
        if (!Object.prototype.hasOwnProperty.call(this.draftCellValues, cellKey)) {
            return undefined;
        }
        return this.draftCellValues[cellKey];
    }

    setDraftCellValue(cellKey, value) {
        this.draftCellValues = {
            ...this.draftCellValues,
            [cellKey]: value
        };
    }

    clearDraftCellValue(cellKey) {
        if (!Object.prototype.hasOwnProperty.call(this.draftCellValues, cellKey)) {
            return;
        }
        const nextDraftValues = { ...this.draftCellValues };
        delete nextDraftValues[cellKey];
        this.draftCellValues = nextDraftValues;
    }

    getClassificationRowClass(classification) {
        if (classification === 'OTS') return 'grid-row_ots';
        if (classification === 'Skilled') return 'grid-row_skilled';
        if (classification === 'Salaried') return 'grid-row_salaried';
        return '';
    }

    getClassificationCellClass(classification) {
        if (classification === 'OTS') return 'grid-cell_ots';
        if (classification === 'Skilled') return 'grid-cell_skilled';
        if (classification === 'Salaried') return 'grid-cell_salaried';
        return '';
    }

    getClassificationTextClass(classification) {
        if (classification === 'OTS') return 'classification-text_ots';
        if (classification === 'Skilled') return 'classification-text_skilled';
        if (classification === 'Salaried') return 'classification-text_salaried';
        if (classification === 'Total') return 'classification-text_total';
        return '';
    }

    updateRows(rows, rowKey, monthKey, value, fillForward = false) {
        const monthOrder = MONTH_COLUMNS.filter((column) => column.key !== 'prevDec').map((column) => column.key);
        const selectedMonthIndex = monthOrder.indexOf(monthKey);

        return rows.map((row) => {
            if (row.key !== rowKey) {
                return row;
            }

            const nextValues = {
                ...row.values,
                [monthKey]: value
            };

            if (fillForward && selectedMonthIndex > -1) {
                for (let index = selectedMonthIndex + 1; index < monthOrder.length; index += 1) {
                    nextValues[monthOrder[index]] = value;
                }
            }

            return {
                ...row,
                values: nextValues
            };
        });
    }

    recalculateNonDriver() {
        const shifts = this.findRow(this.nonDriverRows, 'shifts');
        const jphRow = this.findRow(this.nonDriverRows, 'netJph');
        const paidHoursPerCrew = this.findRow(this.nonDriverRows, 'paidHoursPerCrew');
        const productionDays = this.findRow(this.nonDriverRows, 'productionDays');
        const eqSotDays = this.findRow(this.nonDriverRows, 'eqSotDays');
        const scheduledVolume = this.findRow(this.nonDriverRows, 'scheduledVolume');
        const calculatedVolume = this.findRow(this.nonDriverRows, 'calcVolume');
        const gpsSotDaysWeekends = this.findRow(this.nonDriverRows, 'gpsSotDaysWeekends');
        const stampingEquivalentSotPct = this.findRow(this.nonDriverRows, 'stampingEquivalentSotPct');

        this.nonDriverRows = this.nonDriverRows.map((row) => {
            if (row.key === 'calcVolume') {
                const nextValues = {};
                MONTH_COLUMNS.forEach((column) => {
                    const netJphRaw = jphRow?.values?.[column.key];
                    const paidHoursRaw = paidHoursPerCrew?.values?.[column.key];
                    const productionDaysRaw = productionDays?.values?.[column.key];
                    const eqSotDaysRaw = eqSotDays?.values?.[column.key];
                    const shiftsRaw = shifts?.values?.[column.key];
                    const hasData = [netJphRaw, paidHoursRaw, productionDaysRaw, eqSotDaysRaw, shiftsRaw]
                        .some((value) => !isEmptyMonthValue(value));
                    if (!hasData) {
                        nextValues[column.key] = null;
                        return;
                    }
                    const netJphValue = Number(netJphRaw) || 0;
                    const paidHoursValue = Number(paidHoursRaw) || 0;
                    const productionDaysValue = Number(productionDaysRaw) || 0;
                    const eqSotDaysValue = Number(eqSotDaysRaw) || 0;
                    const shiftsValue = Number(shiftsRaw) || 0;
                    nextValues[column.key] = round(netJphValue * paidHoursValue * (productionDaysValue + eqSotDaysValue) * shiftsValue, 0);
                });

                return {
                    ...row,
                    values: nextValues
                };
            }

            if (row.key === 'volumeVariance') {
                const nextValues = {};
                MONTH_COLUMNS.forEach((column) => {
                    const scheduledRaw = scheduledVolume?.values?.[column.key];
                    const calculatedRaw = this.findRow(this.nonDriverRows, 'calcVolume')?.values?.[column.key];
                    const hasData = !isEmptyMonthValue(scheduledRaw) || !isEmptyMonthValue(calculatedRaw);
                    nextValues[column.key] = hasData ? (Number(scheduledRaw) || 0) - (Number(calculatedRaw) || 0) : null;
                });

                return {
                    ...row,
                    values: nextValues
                };
            }

            if (row.key === 'gpsTotalSotDays') {
                return {
                    ...row,
                    values: buildGpsTotalSotDaysValues(
                        gpsSotDaysWeekends?.values,
                        eqSotDays?.values
                    )
                };
            }

            if (row.key === 'stampingSotEquivalentDaysTotal') {
                return {
                    ...row,
                    values: buildStampingSotEquivalentDaysTotalValues(
                        productionDays?.values,
                        stampingEquivalentSotPct?.values
                    )
                };
            }

            return row;
        });

        const refreshedCalculatedVolume = this.findRow(this.nonDriverRows, 'calcVolume');
        this.nonDriverRows = this.nonDriverRows.map((row) => {
            if (row.key !== 'volumeVariance') {
                return row;
            }

            const nextValues = {};
            MONTH_COLUMNS.forEach((column) => {
                const scheduledRaw = scheduledVolume?.values?.[column.key];
                const calculatedRaw = refreshedCalculatedVolume?.values?.[column.key];
                const hasData = !isEmptyMonthValue(scheduledRaw) || !isEmptyMonthValue(calculatedRaw);
                nextValues[column.key] = hasData ? (Number(scheduledRaw) || 0) - (Number(calculatedRaw) || 0) : null;
            });

            return {
                ...row,
                values: nextValues
            };
        });
    }

    recalculateDriverTotals() {
        const classifications = ['ots', 'skilled', 'salaried'];

        this.applyVacationCoverageReadonlyRules();
        this.applyAssemblyVacationCoverageValues();

        this.driverRows = this.driverRows.map((row) => {
            if (!row.key.startsWith('total-')) {
                return row;
            }

            const classification = row.key.replace('total-', '');
            if (!classifications.includes(classification)) {
                return row;
            }

            const nextValues = this.calculateTotalManpowerValues(classification);

            return {
                ...row,
                values: nextValues
            };
        });
    }

    getTotalManpowerAdjustmentRowsByClassification(classification) {
        const driverSources = ['prod', 'mbc', 'lms', 'vac', 'opplan', 'content', 'sourcing', 'mfgopt', 'launch', 'containment', 'others'];
        return driverSources.reduce((accumulator, prefix) => {
            accumulator[prefix] = this.findRow(this.driverRows, `${prefix}-${classification}`)?.values || {};
            return accumulator;
        }, {});
    }

    calculateTotalManpowerValues(classification) {
        const approvedRow = this.findRow(this.driverRows, `approved-${classification}`);
        const baseRow = this.findRow(this.driverRows, `base-${classification}`);
        const adjustmentRowsByKey = this.getTotalManpowerAdjustmentRowsByClassification(classification);
        return buildTotalManpowerValues(baseRow?.values || {}, approvedRow?.values || {}, adjustmentRowsByKey);
    }

    applyVacationCoverageReadonlyRules() {
        this.driverRows = this.driverRows.map((row) => {
            if (row.key !== 'vac-ots') {
                return row;
            }

            return {
                ...row,
                editable: true
            };
        });
    }

    applyAssemblyVacationCoverageValues() {
        if (!this.hasAssemblyVacationCoverageConfig) {
            return;
        }

        const baseRow = this.findRow(this.driverRows, 'base-ots') || this.findRow(this.nonDriverRows, 'base-ots');
        const approvedRow = this.findRow(this.driverRows, 'approved-ots') || this.findRow(this.nonDriverRows, 'approved-ots');
        const adjustmentRowsByKey = {
            productivity: this.findRow(this.driverRows, 'prod-ots')?.values || {},
            mbc: this.findRow(this.driverRows, 'mbc-ots')?.values || {},
            lms: this.findRow(this.driverRows, 'lms-ots')?.values || {},
            opplan: this.findRow(this.driverRows, 'opplan-ots')?.values || {},
            content: this.findRow(this.driverRows, 'content-ots')?.values || {},
            sourcing: this.findRow(this.driverRows, 'sourcing-ots')?.values || {},
            mfgopt: this.findRow(this.driverRows, 'mfgopt-ots')?.values || {},
            launch: this.findRow(this.driverRows, 'launch-ots')?.values || {},
            containment: this.findRow(this.driverRows, 'containment-ots')?.values || {},
            others: this.findRow(this.driverRows, 'others-ots')?.values || {}
        };
        const currentVacationRow = this.findRow(this.driverRows, 'vac-ots');

        const nextValues = buildAssemblyVacationCoverageValues({
            sector: this.budgetHeader?.sector || this.selectedSector,
            classification: 'OTS',
            vacationPercent: this.vacationCoverageConfig?.vacationPercent,
            entryMonthKey: this.vacationCoverageConfig?.entryMonthKey,
            exitMonthKey: this.vacationCoverageConfig?.exitMonthKey,
            currentValues: currentVacationRow?.values || {},
            baseValues: baseRow?.values || {},
            approvedValues: approvedRow?.values || {},
            adjustmentRowsByKey
        });

        this.patchRow('vac-ots', nextValues, currentVacationRow?.recordId, currentVacationRow?.valueType || 'number');
    }

    findRow(rows, key) {
        return rows.find((row) => row.key === key);
    }

    sumCalculatedHours(classification, metricKey) {
        return MONTH_COLUMNS
            .filter((column) => column.key !== 'prevDec')
            .reduce((total, column) => total + this.calculateHoursForMonth(classification, column.key)[metricKey], 0);
    }

    buildFilterItem(group, value, label, active) {
        return {
            key: `${group}-${value}`,
            group,
            value,
            label,
            className: active ? 'rail-chip rail-chip_active' : 'rail-chip'
        };
    }

    getHighlightedRowClass(baseClass, driverLabel) {
        if (!this.selectedDriverDefault) {
            return baseClass;
        }

        const matches =
            (this.selectedDriverDefault === 'absenteeism' && driverLabel.includes('Absenteeism %')) ||
            (this.selectedDriverDefault === 'nsot' && driverLabel.includes('NSOT %')) ||
            (this.selectedDriverDefault === 'paidHours' && driverLabel.includes('Paid Hours')) ||
            (this.selectedDriverDefault === 'productionDays' && driverLabel.includes('Production Working Days')) ||
            (this.selectedDriverDefault === 'eqSotDays' && driverLabel.includes('EQ SOT Days'));

        return matches ? `${baseClass} row-emphasis` : baseClass;
    }

    calculateHoursForMonth(classification, monthKey) {
        const totalManpowerRaw = this.findRow(this.driverRows, `total-${classification.toLowerCase()}`).values[monthKey];
        const absenteeismRaw = this.findRow(this.nonDriverRows, `absenteeism-${classification.toLowerCase()}`).values[monthKey];
        const nsotRaw = this.findRow(this.nonDriverRows, `nsot-${classification.toLowerCase()}`).values[monthKey];
        const paidHoursRaw = this.findRow(this.nonDriverRows, 'paidHoursPerCrew').values[monthKey];
        const availableDaysRaw = this.findRow(this.nonDriverRows, 'availableDays').values[monthKey];
        const productionDaysRaw = this.findRow(this.nonDriverRows, 'productionDays').values[monthKey];
        const eqSotDaysRaw = this.findRow(this.nonDriverRows, 'eqSotDays').values[monthKey];
        const crewsRaw = this.findRow(this.nonDriverRows, 'crews').values[monthKey];
        const shiftsRaw = this.findRow(this.nonDriverRows, 'shifts').values[monthKey];
        const vacationRow = this.findRow(this.driverRows, `vac-${classification.toLowerCase()}`);
        const additionalStraightAdjustmentRow = this.findRow(this.driverRows, `astadj-${classification.toLowerCase()}`);
        const additionalStraightAdjustmentRaw = additionalStraightAdjustmentRow?.values?.[monthKey];

        const hasSourceData = [
            totalManpowerRaw,
            absenteeismRaw,
            nsotRaw,
            paidHoursRaw,
            availableDaysRaw,
            productionDaysRaw,
            eqSotDaysRaw,
            crewsRaw,
            shiftsRaw,
            additionalStraightAdjustmentRaw
        ].some((value) => !isEmptyMonthValue(value));

        if (!hasSourceData) {
            return {
                combinedAbsence: null,
                scheduledOvertime: null,
                additionalStraightTime: null,
                stHours: null,
                nsotHours: null,
                totalHours: null
            };
        }

        const totalManpower = Number(totalManpowerRaw) || 0;
        const absenteeismPct = percentToDecimal(absenteeismRaw);
        const nsotPct = percentToDecimal(nsotRaw);
        const paidHoursPerCrew = Number(paidHoursRaw) || 0;
        const availableDays = Number(availableDaysRaw) || 0;
        const productionDays = Number(productionDaysRaw) || 0;
        const eqSotDays = Number(eqSotDaysRaw) || 0;
        const crews = Number(crewsRaw) || 1;
        const shifts = Number(shiftsRaw) || 0;

        return calculateHourMetrics({
            totalManpower,
            absenteeismPct,
            nsotPct,
            paidHoursPerCrew,
            availableDays,
            productionDays,
            eqSotDays,
            crews,
            shifts,
            vacationValues: vacationRow?.values || {},
            monthKey,
            classification,
            additionalStraightAdjustment: Number(additionalStraightAdjustmentRaw) || 0
        });
    }

    async initializeWorkbench() {
        if (!this.recordId) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        try {
            const response = await getBudgetContext({ contextRecordId: this.recordId });
            this.budgetOptions = response?.options || [];
            this.contextPlantId = response?.plantId || null;
            this.canEditCurrentBudget = !!response?.canEdit;

            if (!this.budgetOptions.length) {
                this.selectedBudgetId = null;
                this.budgetHeader = null;
                this.errorMessage = this.canEditCurrentBudget
                    ? 'No GWB budgets were found for this plant yet.'
                    : 'No GWB budgets are available for this plant yet.';
                this.resetTables();
                return;
            }

            await this.applyBudgetSelection(response?.selectedBudgetId || this.budgetOptions[0].id, true);
        } catch (error) {
            this.handleError(error, 'Unable to initialize the budget workbench.');
            this.resetTables();
        } finally {
            this.isLoading = false;
        }
    }

    async openRecordInNewTab(recordId) {
        if (!recordId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'GWB_Year__c',
                actionName: 'view'
            }
        }, false);
    }

    async loadBudgetDetail(gwbYearId) {
        if (!gwbYearId) {
            return;
        }

        this.selectedBudgetId = gwbYearId;
        this.isLoading = true;
        this.errorMessage = '';

        try {
            console.log('gwbYearId', gwbYearId);
            const detail = await getBudgetDetail({ gwbYearId });
            console.log('detail', detail);
            this.debugLog('loadBudgetDetail raw detail', detail);
            this.budgetHeader = detail?.header;
            this.normalizeActiveViewTab();
            this.vacationCoverageConfig = detail?.vacationCoverageConfig || null;
            this.canEditCurrentBudget = !!detail?.header?.canEdit;
            this.resetTables();
            this.commentRowsByCellKey = {};
            this.selectedCommentCell = null;
            this.commentDraft = '';
            this.commentMenuOpen = false;
            this.commentMenuStyle = '';
            this.commentModalOpen = false;
            this.draftCellValues = {};

            (detail?.sharedRows || []).forEach((row) => this.applySharedDto(row));
            (detail?.driverRows || []).forEach((row) => this.applyDriverDto(row));
            (detail?.comments || []).forEach((comment) => this.addCommentToState(comment));

            this.debugLog('loadBudgetDetail applied rows', {
                activeBudgetId: gwbYearId,
                sharedRows: this.nonDriverRows.map((row) => ({ key: row.key, recordId: row.recordId, values: row.values })),
                driverRows: this.driverRows.map((row) => ({ key: row.key, recordId: row.recordId, values: row.values }))
            });

            this.recalculateNonDriver();
            this.recalculateDriverTotals();
            this.dirtyRowKeys = new Set();
            this.dirtyCellKeys = new Set();
        } catch (error) {
            console.log('error', error);
            this.handleError(error, 'Unable to load the selected budget.');
            this.resetTables();
        } finally {
            this.isLoading = false;
        }
    }

    resetTables() {
        const sector = this.budgetHeader?.sector || this.selectedSector;
        const baseDefs = getBaseNonDriverDefs(sector);
        const sectorDefs = getSectorSpecificNonDriverDefs(this.budgetHeader?.sector || this.selectedSector);
        this.nonDriverRows = cloneRows([...baseDefs, ...sectorDefs]);
        this.driverRows = cloneRows(DRIVER_ROW_DEFS);
        this.applyVacationCoverageReadonlyRules();
        this.recalculateNonDriver();
        this.recalculateDriverTotals();
        this.dirtyRowKeys = new Set();
        this.dirtyCellKeys = new Set();
    }

    async applyBudgetSelection(budgetId, loadDetail = false) {
        const option = this.budgetOptions.find((item) => item.id === budgetId);
        if (!option) {
            return;
        }

        this.selectedBudgetId = option.id;
        this.selectedYear = option.year || '';
        this.selectedSector = option.sector || '';
        this.selectedVersion = option.version || '';
        this.selectedScope = option.sector || 'Assembly / Polymers';

        if (loadDetail) {
            await this.loadBudgetDetail(option.id);
        }
    }

    handleClassificationFilterChange(event) {
        this.selectedClassificationFilter = event.detail.value || 'All';
    }

    handleDriverFilterChange(event) {
        this.selectedDriverFilter = event.detail.value || 'All';
    }

    handleResetFilters() {
        this.selectedClassificationFilter = 'All';
        this.selectedDriverFilter = 'All';
    }

    handleNonDriverGroupToggle(event) {
        const groupKey = event.currentTarget?.dataset?.groupKey;
        if (groupKey === 'absenteeism') {
            this.nonDriverAbsenteeismExpanded = !this.nonDriverAbsenteeismExpanded;
        } else if (groupKey === 'nsot') {
            this.nonDriverNsotExpanded = !this.nonDriverNsotExpanded;
        }
    }

    async handleRefresh() {
        if (!this.activeBudgetId) {
            return;
        }
        await this.loadBudgetDetail(this.activeBudgetId);
    }

    async handleReadyForPublish() {
        if (this.readyForPublishDisabled) {
            return;
        }

        this.isSaving = true;
        this.errorMessage = '';

        try {
            this.budgetHeader = await updateBudgetState({
                gwbYearId: this.activeBudgetId,
                nextStatus: 'Published'
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Budget updated',
                    message: 'This budget is now marked Published.',
                    variant: 'success'
                })
            );
            await this.initializeWorkbench();
        } catch (error) {
            this.handleError(error, 'Unable to update the budget state.');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSave() {
        if (!this.activeBudgetId) {
            this.errorMessage = 'Select an existing GWB budget before editing or saving.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Select a budget first',
                    message: this.errorMessage,
                    variant: 'warning'
                })
            );
            return;
        }

        this.isSaving = true;
        this.errorMessage = '';

        try {
            this.syncVisibleInputsToState();
            this.validateAdditionalStraightAdjustmentJustifications();
            const payload = this.buildSavePayload();
            this.debugLog('handleSave payload', payload);
            if (!payload.sharedRows.length && !payload.driverRows.length) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Nothing to save',
                        message: 'No editable changes were detected.',
                        variant: 'info'
                    })
                );
                return;
            }

            const result = await saveBudgetRows({
                gwbYearId: payload.gwbYearId,
                sharedRowsJson: JSON.stringify(payload.sharedRows),
                driverRowsJson: JSON.stringify(payload.driverRows)
            });
            this.debugLog('handleSave result', result);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Budget saved',
                    message: result?.message || 'Budget changes saved successfully.',
                    variant: 'success'
                })
            );
            await this.loadBudgetDetail(payload.gwbYearId);
        } catch (error) {
            this.handleError(error, 'Unable to save budget changes.');
        } finally {
            this.isSaving = false;
        }
    }

    async handleTableSave(event) {
        const tableName = event.target.dataset.tableSave;
        let rowKeys = [];
        let successMessage = 'Budget changes saved successfully.';

        if (tableName === 'nonDriverShared') {
            rowKeys = this.nonDriverSharedRowKeys;
            successMessage = 'Non-Driver inputs saved successfully.';
        } else if (tableName === 'nonDriverClassification') {
            rowKeys = this.nonDriverClassificationRowKeys;
            successMessage = 'Classification inputs saved successfully.';
        } else if (tableName === 'driver') {
            rowKeys = this.driverEditableRowKeys;
            successMessage = 'Manpower adjustments saved successfully.';
        }

        if (!rowKeys.length) {
            return;
        }

        await this.saveRowsByKeys(rowKeys, successMessage);
    }

    handleCreateDraft() {
        if (this.disableCreateDraft) {
            return;
        }

        this.selectedCloneVersion = '';
        this.cloneModalOpen = true;
    }

    handleCloseCloneModal() {
        this.cloneModalOpen = false;
        this.selectedCloneVersion = '';
    }

    handleCloneVersionChange(event) {
        this.selectedCloneVersion = event.detail.value;
    }

    async handleConfirmCreateDraft() {
        if (this.disableCreateDraft) {
            return;
        }

        if (!this.selectedCloneVersion) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'M-Schedule Required',
                    message: 'Select an M-Schedule Data Point before continuing.',
                    variant: 'error'
                })
            );
            return;
        }

        this.isSaving = true;
        this.errorMessage = '';

        try {
            const result = await cloneDraftTargets({
                targetIds: [this.activeBudgetId],
                versionValue: this.selectedCloneVersion
            });
            const clonedTargetId = result?.targetIds?.[0] || null;
            const response = await getBudgetContext({ contextRecordId: this.recordId });

            this.budgetOptions = response?.options || [];
            this.contextPlantId = response?.plantId || this.contextPlantId;
            this.canEditCurrentBudget = !!response?.canEdit;

            if (clonedTargetId && this.budgetOptions.some((option) => option.id === clonedTargetId)) {
                await this.applyBudgetSelection(clonedTargetId, true);
            }

            this.handleCloseCloneModal();
            await this.openRecordInNewTab(clonedTargetId);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Target cloned',
                    message: 'The target was cloned successfully.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.handleError(error, 'Unable to clone the target.');
        } finally {
            this.isSaving = false;
        }
    }

    handleCommentDraftChange(event) {
        this.commentDraft = event.target.value;
    }

    handleCellContextMenu(event) {
        event.preventDefault();

        if (event.currentTarget.dataset.commentable !== 'true') {
            this.commentMenuOpen = false;
            return;
        }

        const tableName = event.currentTarget.dataset.table;
        const rowKey = event.currentTarget.dataset.rowKey;
        const monthKey = event.currentTarget.dataset.monthKey;

        this.selectCommentCell(tableName, rowKey, monthKey);
        this.commentMenuStyle = `top:${event.clientY + 8}px;left:${event.clientX + 8}px;`;
        this.commentMenuOpen = true;
    }

    handleDismissCommentMenu() {
        this.commentMenuOpen = false;
    }

    handleOpenCommentModal() {
        if (!this.selectedCommentCell) {
            this.commentMenuOpen = false;
            return;
        }
        this.commentMenuOpen = false;
        this.editingCommentId = null;
        this.commentModalOpen = true;
    }

    handleOpenJustificationFromMenu() {
        if (!this.selectedCellSupportsJustification) {
            this.commentMenuOpen = false;
            return;
        }

        const monthKey = this.selectedCommentCell.monthKey;
        this.commentMenuOpen = false;
        this.selectCommentCell('hoursJustification', getAdditionalStraightJustificationRowKey(), monthKey);
        const existingReason = this.getAdditionalStraightReasonComment(monthKey);
        this.editingCommentId = existingReason?.id || null;
        this.commentDraft = existingReason?.commentText || '';
        this.commentModalOpen = true;
    }

    handleCloseCommentModal() {
        this.commentModalOpen = false;
        this.editingCommentId = null;
        this.commentDraft = '';
    }

    handleRecentCommentClick(event) {
        const tableName = event.currentTarget.dataset.table;
        const rowKey = event.currentTarget.dataset.rowKey;
        const monthKey = event.currentTarget.dataset.monthKey;

        this.selectCommentCell(tableName, rowKey, monthKey);
        this.editingCommentId = null;
        this.commentModalOpen = true;
    }

    handleEditComment(event) {
        this.editingCommentId = event.currentTarget.dataset.commentId;
        this.commentDraft = event.currentTarget.dataset.commentText || '';
    }

    handleOpenJustificationModal(event) {
        event.preventDefault();
        event.stopPropagation();
        const targetTableName = event.currentTarget.dataset.table;
        const targetRowKey = event.currentTarget.dataset.rowKey;
        const targetMonthKey = event.currentTarget.dataset.monthKey || 'jan';

        this.selectCommentCell(targetTableName, targetRowKey, targetMonthKey);
        const existingReason = targetTableName === 'hoursJustification'
            ? this.getAdditionalStraightReasonComment(targetMonthKey)
            : null;
        this.editingCommentId = existingReason?.id || null;
        this.commentDraft = existingReason?.commentText || '';
        this.commentModalOpen = true;
    }

    async handleSaveComment() {
        if (this.disableCommentSave) {
            return;
        }

        this.isSavingComment = true;
        this.errorMessage = '';

        try {
            const existingReason = this.selectedCommentCell.tableName === 'hoursJustification'
                ? this.getAdditionalStraightReasonComment(this.selectedCommentCell.monthKey)
                : null;
            const savedComment = await saveBudgetComment({
                gwbYearId: this.activeBudgetId,
                commentId: this.editingCommentId || existingReason?.id || null,
                tableName: this.selectedCommentCell.tableName,
                rowKey: this.selectedCommentCell.rowKey,
                rowLabel: this.selectedCommentCell.rowLabel,
                monthKey: this.selectedCommentCell.monthKey,
                classification: this.selectedCommentCell.classification,
                commentText: this.commentDraft.trim(),
                valueSnapshot: this.selectedCommentCell.valueSnapshot
            });

            this.addCommentToState(savedComment);
            if (savedComment?.cellKey) {
                this.sessionSavedCommentCellKeys.add(savedComment.cellKey);
            }
            this.commentDraft = '';
            this.editingCommentId = null;
            this.commentModalOpen = true;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: this.selectedCommentCell.tableName === 'hoursJustification' ? 'Reason saved' : 'Comment saved',
                    message:
                        this.selectedCommentCell.tableName === 'hoursJustification'
                            ? 'The monthly reason was saved successfully.'
                            : 'The budget comment was added successfully.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.handleError(error, 'Unable to save the budget comment.');
        } finally {
            this.isSavingComment = false;
        }
    }

    handleCellFocus(event) {
        const tableName = event.currentTarget.dataset.table;
        const rowKey = event.currentTarget.dataset.rowKey;
        const monthKey = event.currentTarget.dataset.monthKey;
        this.selectCommentCell(tableName, rowKey, monthKey);
    }

    handleGridInputWheel(event) {
        event.currentTarget.blur();
    }

    handleCellCommentClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const tableName = event.currentTarget.dataset.table;
        const rowKey = event.currentTarget.dataset.rowKey;
        const monthKey = event.currentTarget.dataset.monthKey;
        this.selectCommentCell(tableName, rowKey, monthKey);
        this.editingCommentId = null;
        this.commentModalOpen = true;
    }

    buildSavePayload(rowKeys = null) {
        const sharedRows = [];
        const driverRows = [];
        const rowKeyFilter = rowKeys ? new Set(rowKeys) : null;
        const upsertSharedRow = (payload) => {
            const existingIndex = sharedRows.findIndex(
                (row) => row.parameter === payload.parameter && row.classification === payload.classification
            );
            if (existingIndex >= 0) {
                sharedRows[existingIndex] = payload;
                return;
            }
            sharedRows.push(payload);
        };

        this.dirtyRowKeys.forEach((rowKey) => {
            if (rowKeyFilter && !rowKeyFilter.has(rowKey)) {
                return;
            }
            const sharedMeta = SHARED_ROW_META[rowKey];
            const driverMeta = DRIVER_ROW_META[rowKey];
            const row = this.findRow(this.nonDriverRows, rowKey) || this.findRow(this.driverRows, rowKey);

            if (!row) {
                return;
            }

            if (sharedMeta?.persist) {
                upsertSharedRow({
                    recordId: row.recordId || null,
                    objectApiName: sharedMeta.objectApiName,
                    section: sharedMeta.section,
                    parameter: sharedMeta.parameter,
                    classification: sharedMeta.classification,
                    valueType: sharedMeta.valueType,
                    values: { ...row.values }
                });
                return;
            }

            if (driverMeta?.persist) {
                driverRows.push({
                    recordId: row.recordId || null,
                    objectApiName: driverMeta.objectApiName,
                    driver: driverMeta.driver,
                    classification: driverMeta.classification,
                    valueType: 'number',
                    values: { ...row.values }
                });
            }
        });

        if (this.shouldSyncBaseHeadcountOnSave(rowKeyFilter)) {
            ['ots', 'skilled', 'salaried'].forEach((classification) => {
                const syncedPayload = this.buildBaseHeadcountSyncPayload(`base-${classification}`, `total-${classification}`);
                if (syncedPayload) {
                    upsertSharedRow(syncedPayload);
                }
            });
        }

        return {
            gwbYearId: this.activeBudgetId,
            sharedRows,
            driverRows
        };
    }

    shouldSyncBaseHeadcountOnSave(rowKeyFilter = null) {
        return Array.from(this.dirtyRowKeys).some((rowKey) => {
            if (rowKeyFilter && !rowKeyFilter.has(rowKey)) {
                return false;
            }
            return !!DRIVER_ROW_META[rowKey];
        });
    }

    buildBaseHeadcountSyncPayload(baseRowKey, totalRowKey) {
        const sharedMeta = SHARED_ROW_META[baseRowKey];
        const baseRow = this.findRow(this.driverRows, baseRowKey) || this.findRow(this.nonDriverRows, baseRowKey);
        const classification = totalRowKey.replace('total-', '');
        if (!sharedMeta?.persist || !baseRow || !classification) {
            return null;
        }

        const syncedValues = { ...baseRow.values };
        const calculatedTotalValues = this.calculateTotalManpowerValues(classification);
        MONTH_COLUMNS
            .filter((column) => column.key !== 'prevDec')
            .forEach((column) => {
                syncedValues[column.key] = calculatedTotalValues?.[column.key] ?? 0;
            });

        return {
            recordId: baseRow.recordId || null,
            objectApiName: sharedMeta.objectApiName,
            section: sharedMeta.section,
            parameter: sharedMeta.parameter,
            classification: sharedMeta.classification,
            valueType: sharedMeta.valueType,
            values: syncedValues
        };
    }

    hasDirtyRows(rowKeys) {
        return rowKeys.some((rowKey) => this.dirtyRowKeys.has(rowKey));
    }

    validateAdditionalStraightAdjustmentJustifications(rowKeys = null) {
        const targetRowKeys = rowKeys
            ? ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.filter((rowKey) => rowKeys.includes(rowKey))
            : [...ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS];
        const missing = [];

        targetRowKeys.forEach((rowKey) => {
            const row = this.findRow(this.driverRows, rowKey);
            if (!row) {
                return;
            }

            MONTH_COLUMNS
                .filter((column) => column.key !== 'prevDec')
                .forEach((column) => {
                    const cellKey = `driver:${rowKey}:${column.key}`;
                    if (!this.dirtyCellKeys.has(cellKey)) {
                        return;
                    }

                    const value = Number(row.values?.[column.key]) || 0;
                    if (value === 0) {
                        return;
                    }

                    if (this.hasAdditionalStraightReasonForMonth(column.key)) {
                        return;
                    }

                    missing.push(this.getMonthLabel(column.key));
                });
        });

        if (!missing.length) {
            return;
        }

        throw new Error(`Add a reason for each adjusted Additional ST month before saving: ${[...new Set(missing)].join(', ')}.`);
    }

    getAdjustmentMonthsMissingComment(row, requireDirty = false) {
        if (!row) {
            return [];
        }
        return MONTH_COLUMNS
            .filter((column) => column.key !== 'prevDec')
            .filter((column) => {
                const value = Number(row.values?.[column.key]) || 0;
                if (value === 0) {
                    return false;
                }
                const cellKey = `driver:${row.key}:${column.key}`;
                if (requireDirty && !this.dirtyCellKeys.has(cellKey)) {
                    return false;
                }
                return !this.hasAdditionalStraightReasonForMonth(column.key);
            })
            .map((column) => column.key);
    }

    getMonthLabel(monthKey) {
        return MONTH_COLUMNS.find((column) => column.key === monthKey)?.label || monthKey;
    }

    async saveRowsByKeys(rowKeys, successMessage) {
        if (!this.activeBudgetId) {
            this.errorMessage = 'Select an existing GWB budget before editing or saving.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Select a budget first',
                    message: this.errorMessage,
                    variant: 'warning'
                })
            );
            return;
        }

        this.isSaving = true;
        this.errorMessage = '';

        try {
            this.syncVisibleInputsToState();
            this.validateAdditionalStraightAdjustmentJustifications(rowKeys);
            const payload = this.buildSavePayload(rowKeys);
            this.debugLog('saveRowsByKeys payload', {
                rowKeys,
                payload
            });
            if (!payload.sharedRows.length && !payload.driverRows.length) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Nothing to save',
                        message: 'No editable changes were detected in this table.',
                        variant: 'info'
                    })
                );
                return;
            }

            const result = await saveBudgetRows({
                gwbYearId: payload.gwbYearId,
                sharedRowsJson: JSON.stringify(payload.sharedRows),
                driverRowsJson: JSON.stringify(payload.driverRows)
            });
            this.debugLog('saveRowsByKeys result', result);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Budget saved',
                    message: result?.message || successMessage,
                    variant: 'success'
                })
            );
            await this.loadBudgetDetail(payload.gwbYearId);
        } catch (error) {
            this.handleError(error, 'Unable to save budget changes.');
        } finally {
            this.isSaving = false;
        }
    }

    applySharedDto(dto) {
        const rowKey = this.mapSharedRowKey(dto);
        this.debugLog('applySharedDto', { dto, mappedRowKey: rowKey });
        if (!rowKey) {
            return;
        }

        this.patchRow(rowKey, dto.values, dto.recordId, dto.valueType);
    }

    applyDriverDto(dto) {
        const rowKey = this.mapDriverRowKey(dto);
        this.debugLog('applyDriverDto', { dto, mappedRowKey: rowKey });
        if (!rowKey) {
            return;
        }

        this.patchRow(rowKey, dto.values, dto.recordId, dto.valueType);
    }

    patchRow(rowKey, values, recordId, valueType) {
        const patch = (row) => {
            if (row.key !== rowKey) {
                return row;
            }

            return {
                ...row,
                recordId: recordId || row.recordId,
                valueType: valueType || row.valueType,
                values: {
                    ...row.values,
                    ...values
                }
            };
        };

        this.nonDriverRows = this.nonDriverRows.map(patch);
        this.driverRows = this.driverRows.map(patch);
    }

    mapSharedRowKey(dto) {
        const classification = this.normalizeSharedClassification(dto.classification);
        const parameter = this.normalizeSharedParameter(dto.parameter);
        const sectorKey = normalizeSectorKey(this.budgetHeader?.sector || this.selectedSector);
        const requiresClassification = [
            'base headcount',
            'approved target',
            'additional straight time hours adjustment',
            'absenteeism %',
            'nsot %'
        ];
        if (requiresClassification.includes(parameter) && !classification) {
            return null;
        }

        if (parameter === 'crews') return 'crews';
        if (parameter === 'shifts') return 'shifts';
        if (parameter === 'net/net jph') return 'netJph';
        if (parameter === 'calculated volume incl. sot' || parameter === 'calculated volume incl. sot days') return 'calcVolume';
        if (parameter === 'scheduled volume') return 'scheduledVolume';
        if (parameter === 'volume variance') return 'volumeVariance';
        if (parameter === 'paid hours per crew') return 'paidHoursPerCrew';
        if (parameter === 'available working days/month') return 'availableDays';
        if (parameter === 'production working days/month') return 'productionDays';
        if (parameter === 'eq sot days') return 'eqSotDays';
        if (parameter === 'base headcount') return `base-${classification.toLowerCase()}`;
        if (parameter === 'approved target') return `approved-${classification.toLowerCase()}`;
        if (parameter === 'additional straight time hours adjustment') return `astadj-${classification.toLowerCase()}`;
        if (parameter === 'absenteeism %') return `absenteeism-${classification.toLowerCase()}`;
        if (parameter === 'nsot %') return `nsot-${classification.toLowerCase()}`;
        if (parameter === 'final assembly line jph') return 'gpsFinalAssemblyLineJph';
        if (parameter === 'daily op plan volume') {
            if (sectorKey === 'gps') return 'gpsDailyOpPlanVolume';
            if (sectorKey === 'stamping') return 'stampingDailyOpPlanVolume';
        }
        if (parameter === 'sot days (weekends)') return 'gpsSotDaysWeekends';
        if (parameter === 'total sot days') return 'gpsTotalSotDays';
        if (parameter === 'equivalent units volume') return 'stampingEquivalentUnitsVolume';
        if (parameter === 'harbour strokes hpu') return 'stampingHarbourStrokesHpu';
        if (parameter === 'scheduled volume pieces') return 'stampingScheduledVolumePieces';
        if (parameter === 'scheduled volume strokes') return 'stampingScheduledVolumeStrokes';
        if (parameter === 'equivalent sot %') return 'stampingEquivalentSotPct';
        if (parameter === 'sot percent from weekend days') return 'stampingSotPercentWeekendDays';
        if (parameter === 'sot from line time') return 'stampingSotFromLineTime';
        if (parameter === 'sot equivalent days total') return 'stampingSotEquivalentDaysTotal';

        return null;
    }

    normalizeSharedParameter(value) {
        return String(value || '')
            .trim()
            .toLowerCase()
            .replace(/\s*\/\s*/g, '/')
            .replace(/\s+/g, ' ');
    }

    mapDriverRowKey(dto) {
        const normalizedClassification = this.normalizeDriverClassification(dto.classification);
        if (!normalizedClassification) {
            return null;
        }
        const classification = normalizedClassification.toLowerCase();
        const driverMap = {
            Productivity: 'prod',
            ARC: 'mbc',
            LMS: 'lms',
            'Op Plan': 'opplan',
            'Vacation Replacement': 'vac',
            Content: 'content',
            Sourcing: 'sourcing',
            'Mfg Opt': 'mfgopt',
            Launch: 'launch',
            Containment: 'containment',
            'Other/Excess': 'others'
        };
        const prefix = driverMap[dto.driver];
        return prefix ? `${prefix}-${classification}` : null;
    }

    normalizeSharedClassification(value) {
        if (!value) {
            return '';
        }
        if (value === 'OTS' || value === 'OST') {
            return 'OTS';
        }
        if (value === 'Skilled' || value === 'SK') {
            return 'Skilled';
        }
        if (value === 'Salaried' || value === 'SAL') {
            return 'Salaried';
        }
        return value;
    }

    normalizeDriverClassification(value) {
        if (!value) {
            return '';
        }
        if (value === 'OTS') {
            return 'OTS';
        }
        if (value === 'Skilled' || value === 'SK') {
            return 'Skilled';
        }
        if (value === 'Salaried' || value === 'SAL') {
            return 'Salaried';
        }
        return value;
    }

    handleError(error, fallbackMessage) {
        const message = error?.body?.message || error?.message || fallbackMessage;
        this.errorMessage = message;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Budget workbench error',
                message,
                variant: 'error'
            })
        );
    }

    selectCommentCell(tableName, rowKey, monthKey) {
        let row;
        let monthLabel = MONTH_COLUMNS.find((column) => column.key === monthKey)?.label || monthKey;

        if (tableName === 'hoursJustification') {
            row = {
                driver: ADDITIONAL_ST_JUSTIFICATION_LABEL,
                classification: 'Shared',
                values: {
                    [monthKey]: ''
                },
                valueType: 'text'
            };
        } else if (tableName === 'hours') {
            row = this.hourCalculationRows.find((hourRow) => hourRow?.key === rowKey);
        } else if (tableName === 'driver') {
            row = this.findRow(this.driverRows, rowKey);
        } else {
            row = this.findRow(this.nonDriverRows, rowKey);
        }

        if (!row) {
            this.selectedCommentCell = null;
            return;
        }

        this.selectedCommentCell = {
            cellKey: `${tableName}:${rowKey}:${monthKey}`,
            tableName,
            rowKey,
            rowLabel: row.driver,
            monthKey,
            monthLabel,
            classification: row.classification,
            valueSnapshot: formatValue(row.values[monthKey], row.valueType)
        };
    }

    addCommentToState(comment) {
        if (!comment?.cellKey) {
            return;
        }

        const existingComments = this.commentRowsByCellKey[comment.cellKey] || [];
        this.commentRowsByCellKey = {
            ...this.commentRowsByCellKey,
            [comment.cellKey]: [comment, ...existingComments.filter((existing) => existing.id !== comment.id)]
        };
    }

    getCellCommentCount(tableName, rowKey, monthKey) {
        const cellKey = `${tableName}:${rowKey}:${monthKey}`;
        return (this.commentRowsByCellKey[cellKey] || []).length;
    }

    getAdditionalStraightReasonComment(monthKey) {
        const sharedMonthlyKey = `hoursJustification:${getAdditionalStraightJustificationRowKey()}:${monthKey}`;
        const sharedMonthlyComment = this.commentRowsByCellKey[sharedMonthlyKey]?.[0];
        if (sharedMonthlyComment) {
            return sharedMonthlyComment;
        }

        // Backward compatibility for older saved records that used
        // classification/year-based reason keys.
        for (const legacyRowKey of ['astjust-ots', 'astjust-skilled', 'astjust-salaried']) {
            const legacyMonthlyKey = `hoursJustification:${legacyRowKey}:${monthKey}`;
            const legacyYearKey = `hoursJustification:${legacyRowKey}:year`;
            const legacyComment = this.commentRowsByCellKey[legacyMonthlyKey]?.[0] || this.commentRowsByCellKey[legacyYearKey]?.[0];
            if (legacyComment) {
                return legacyComment;
            }
        }

        return null;
    }

    hasAdditionalStraightReasonForMonth(monthKey) {
        return !!this.getAdditionalStraightReasonComment(monthKey);
    }

    get latestCommentCellKey() {
        const latestComment = this.recentComments?.[0];
        return latestComment?.cellKey || null;
    }

    isPendingCommentCell(tableName, rowKey, monthKey) {
        if (!this.commentModalOpen || !this.selectedCommentCell) {
            return false;
        }
        return this.selectedCommentCell.tableName === tableName
            && this.selectedCommentCell.rowKey === rowKey
            && this.selectedCommentCell.monthKey === monthKey
            && !!this.commentDraft?.trim();
    }

    getCommentIconClass(tableName, rowKey, monthKey) {
        const cellKey = `${tableName}:${rowKey}:${monthKey}`;
        if (this.isPendingCommentCell(tableName, rowKey, monthKey)) {
            return 'cell-comment-icon cell-comment-icon_pending';
        }
        if (this.sessionSavedCommentCellKeys.has(cellKey)) {
            return 'cell-comment-icon cell-comment-icon_session';
        }
        return 'cell-comment-icon cell-comment-icon_existing';
    }
}