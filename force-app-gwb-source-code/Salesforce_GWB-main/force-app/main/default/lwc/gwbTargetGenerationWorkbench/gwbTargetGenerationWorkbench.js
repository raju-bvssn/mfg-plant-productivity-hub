import { LightningElement, api, track } from 'lwc';
import getBudgetScreen from '@salesforce/apex/GwbTargetWorkbenchController.getBudgetScreen';
import saveBudgetRows from '@salesforce/apex/GwbTargetWorkbenchController.saveBudgetRows';
import saveBudgetComment from '@salesforce/apex/GwbTargetWorkbenchController.saveBudgetComment';
import updateTargetStatus from '@salesforce/apex/GwbTargetWorkbenchController.updateTargetStatus';
import cloneDraftTargets from '@salesforce/apex/DraftTargetController.cloneDraftTargets';
import getMScheduleOptions from '@salesforce/apex/DraftTargetController.getMScheduleOptions';
import publishSelectedTargets from '@salesforce/apex/DraftTargetController.publishSelectedTargets';
import hasPlantAdminPermission from '@salesforce/customPermission/Plant_Admin';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

const MONTH_COLUMNS = [
    { key: 'prevDec', label: "DEC'26" },
    { key: 'jan', label: 'JAN' },
    { key: 'feb', label: 'FEB' },
    { key: 'mar', label: 'MAR' },
    { key: 'apr', label: 'APR' },
    { key: 'may', label: 'MAY' },
    { key: 'jun', label: 'JUN' },
    { key: 'jul', label: 'JUL' },
    { key: 'aug', label: 'AUG' },
    { key: 'sep', label: 'SEP' },
    { key: 'oct', label: 'OCT' },
    { key: 'nov', label: 'NOV' },
    { key: 'dec', label: 'DEC' }
];

function deepClone(value) {
    return JSON.parse(JSON.stringify(value));
}

function classificationSuffix(classification) {
    const normalized = String(classification || '').trim().toLowerCase();
    if (normalized === 'ots') {
        return 'ots';
    }
    if (normalized === 'skilled') {
        return 'skilled';
    }
    if (normalized === 'salaried' || normalized === 'salary') {
        return 'salaried';
    }
    if (normalized === 'total') {
        return 'total';
    }
    return '';
}

function classificationSortRank(classification) {
    const normalized = String(classification || '').trim().toLowerCase();
    if (normalized === 'ots' || normalized === 'ost') {
        return 1;
    }
    if (normalized === 'skilled' || normalized === 'sk') {
        return 2;
    }
    if (normalized === 'salaried' || normalized === 'salary' || normalized === 'sal') {
        return 3;
    }
    if (normalized === 'total') {
        return 4;
    }
    return 5;
}

function familyClassificationSortRank(row) {
    const normalizedLineType = String(row?.lineType || '').trim().toLowerCase();
    const normalizedClassification = String(row?.classification || '').trim().toLowerCase();
    if (normalizedLineType === 'total' || normalizedClassification === 'total') {
        return 0;
    }
    return classificationSortRank(row?.classification);
}

function normalizeRenderText(value) {
    return String(value || '')
        .toLowerCase()
        .replace(/\s*\/\s*/g, '/')
        .replace(/\s+/g, ' ')
        .trim();
}

function formatTargetVersion(version, year, mScheduleVersion) {
    const explicitVersion = String(version || '').trim();
    const scheduleYearMatch = explicitVersion.match(/^(\d{2}\+\d{2})[_\s-]+(\d{4})$/);
    if (scheduleYearMatch) {
        return `${scheduleYearMatch[2]}_${scheduleYearMatch[1]}`;
    }
    if (explicitVersion) {
        return explicitVersion;
    }
    const yearValue = String(year || '').trim();
    const scheduleValue = String(mScheduleVersion || '').trim();
    if (yearValue && scheduleValue) {
        return `${yearValue}_${scheduleValue}`;
    }
    return yearValue || scheduleValue;
}

function normalizeFamilyIdentity(value) {
    const normalized = normalizeRenderText(value);
    if (normalized === 'base headcount' || normalized === 'base headcount (non supp, no apprentices)') {
        return 'base headcount (non supp, no apprentices)';
    }
    if (
        normalized === 'total manpower (include target changes)' ||
        normalized === 'total manpower (incl prev ye approved target changes)' ||
        normalized === 'total manpower'
    ) {
        return 'total manpower (include target changes)';
    }
    if (
        normalized === 'advanced target changes' ||
        normalized === 'approved target' ||
        normalized === 'previous ye approved target changes'
    ) {
        return 'previous ye approved target changes';
    }
    if (normalized === 'vacation replacement' || normalized === 'vacation coverage') {
        return 'vacation replacement';
    }
    if (normalized === 'op plan' || normalized === 'op plan changes') {
        return 'op plan';
    }
    if (normalized === 'content' || normalized === 'content changes') {
        return 'content';
    }
    if (normalized === 'other/excess' || normalized === 'other / excess') {
        return 'other/excess';
    }
    if (normalized === 'mfg opt' || normalized === 'mfgop' || normalized === 'mfgopt') {
        return 'mfg opt';
    }
    return normalized;
}

const MONTH_KEYS = MONTH_COLUMNS.map((column) => column.key);
const EDITABLE_MONTH_KEYS = MONTH_KEYS.filter((monthKey) => monthKey !== 'prevDec');
const HOURS_FORMULA_KEYS = new Set([
    'combinedAbsence',
    'scheduledOvertime',
    'additionalStraightTime',
    'stHours',
    'nsotHours',
    'totalHours',
    'ahpuMonthly',
    'ahpuYtd',
    'whpuMonthly'
]);
const ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS = ['astadj-ots', 'astadj-skilled', 'astadj-salaried'];
const ADDITIONAL_ST_REASON_ROW_KEY = 'astjust-monthly';
const CUMULATIVE_AVERAGE_HC_FAMILIES = new Set([
    'productivity',
    'mbc',
    'lms',
    'op plan',
    'vacation replacement',
    'content',
    'sourcing',
    'launch',
    'mfg opt',
    'containment',
    'other/excess'
]);
const COMMENT_ROW_KEY_ALIASES = {
    'advanced-ots': 'approved-ots',
    'advanced-skilled': 'approved-skilled',
    'advanced-salaried': 'approved-salaried',
    'vacation coverage-ots': 'vac-ots',
    'vacation coverage-skilled': 'vac-skilled',
    'vacation coverage-salaried': 'vac-salaried',
    'vacation replacement-ots': 'vac-ots',
    'vacation replacement-skilled': 'vac-skilled',
    'vacation replacement-salaried': 'vac-salaried'
};

const FORMULA_TEXT_BY_KEY = {
    crews: 'Input value: monthly Number of Crews used in downstream volume and hours calculations.',
    shifts: 'Input value: monthly Number of Shifts used in downstream volume and hours calculations.',
    netJph: 'Input value: monthly Net / Net JPH used in downstream volume and WHPU calculations.',
    paidHoursPerCrew: 'Input value: monthly Paid Hours Per CREW used in calculated volume and hours formulas.',
    availableDays: 'Input value: monthly Available Working Days / Month.',
    productionDays: 'Input value: monthly Production Working Days / Month.',
    eqSotDays: 'Input value: monthly EQ SOT Days. In GPS this also contributes to Total SOT Days; in Press it contributes to equivalent SOT calculations.',
    calcVolume: 'Calculated Volume = Net/Net JPH x Paid Hours Per CREW x (Production Working Days + EQ SOT Days) x Number of Shifts',
    scheduledVolume: 'Scheduled Volume is the monthly target volume input copied from the target draft / M-Schedule source and remains editable.',
    volumeVariance: 'Scheduled Volume minus Calculated Volume = Scheduled Volume - Calculated Volume incl. SOT days',
    gpsTotalSotDays: 'Total SOT Days = SOT days (Weekends) + EQ SOT Days.',
    stampingEquivalentSotPct: 'Input value: Equivalent SOT %.',
    stampingSotPercentWeekendDays: 'Input value: SOT percent from weekend days.',
    stampingSotFromLineTime: 'Input value: SOT from line time.',
    stampingSotEquivalentDaysTotal: 'SOT equivalent days total = Production Working Days / Month x Equivalent SOT % (Press only).',
    baseHeadcount: 'Base Headcount is the starting manpower baseline by classification. Previous December comes from the prior locked target and the target-year months follow the generated baseline logic.',
    approvedTargetChanges: 'Approved Target Changes uses previous-year December as the editable baseline input row for headcount carry-forward and target manpower calculations.',
    totalManpower: 'Total Manpower formula: Previous December is Base Headcount Prev Dec + Approved Target Prev Dec. Jan starts from previous December, then each month rolls forward using the same classification total plus the applicable adjustment rows for that month.',
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
    productivityAdjustment: 'Productivity adjustment row entered by classification. These values change Total Manpower for the same classification and month.',
    opPlanAdjustment: 'Op Plan adjustment row entered by classification. These values change Total Manpower for the same classification and month.',
    contentAdjustment: 'Content adjustment row entered by classification. These values change Total Manpower for the same classification and month.',
    sourcingAdjustment: 'Sourcing adjustment row entered by classification. These values change Total Manpower for the same classification and month.',
    otherExcessAdjustment: 'Other / Excess adjustment row entered by classification. These values change Total Manpower for the same classification and month.',
    launchAdjustment: 'Launch adjustment row entered by classification. These values change Total Manpower for the same classification and month.',
    mfgOptAdjustment: 'Mfg Opt adjustment row entered by classification. These values change Total Manpower for the same classification and month.',
    arcAdjustment: 'ARC adjustment row entered by classification. These values change Total Manpower for the same classification and month.',
    placeholderAdjustment: 'Placeholder adjustment row entered by classification. These values change Total Manpower for the same classification and month.',
    stHours: "ST Hours = Total Manpower x (1 - (Absenteeism % + Summer VRO %)) x Paid Hours Per CREW x Production Working Days x (Shifts / Crews) + Additional ST Hours",
    nsotHours: 'NSOT Hours by classification = (ST Hours + Scheduled Overtime Hours) x NSOT %. Total row = OTS + Skilled + Salaried for the same month.',
    totalHours: 'Total Hours = ST Hours + NSOT Hours + Scheduled Overtime Hours',
    ahpuMonthly: 'AHPU Monthly = Total Hours / Scheduled Volume. For Stamping targets this uses Scheduled Volume Pieces and multiplies by 100.',
    ahpuYtd: 'AHPU YTD = cumulative Total Hours / cumulative Scheduled Volume. For Stamping targets this uses cumulative Scheduled Volume Pieces and multiplies by 100.',
    whpuMonthly: 'WHPU Monthly = (Total Manpower - sumproduct(Total Manpower by classification, Absenteeism % by classification)) / Net/Net JPH / Number of Crews.',
    prodPct: 'Productivity % = (Productivity + ARC/MBC + LMS adjustments) / previous-year total manpower.',
    averageTotal: 'Average Total = Jan-Dec average of total manpower across OTS, Skilled, and Salaried.',
    stHoursTile: "ST Hours card = Jan-Dec sum of ST Hours including Additional ST Hours across OTS, Skilled, and Salaried.",
    nsotHoursTile: 'NSOT Hours card = Jan-Dec sum of NSOT Hours across OTS, Skilled, and Salaried.',
    nsotCyPct: 'NSOT CY % = Jan-Dec NSOT Hours / (Jan-Dec ST Hours + Jan-Dec Scheduled Overtime Hours).',
    sotCyPct: 'SOT CY % = Jan-Dec Scheduled Overtime Hours / Jan-Dec ST Hours.',
    additionalSt: 'Additional ST Hours card = Jan-Dec sum of calculated Additional ST Hours plus adjustments across all classifications.',
    totalHoursTile: 'Total Hours card = Jan-Dec sum of Total Hours for OTS + Skilled + Salaried.',
    pyeHeadcount: 'PYE Headcount = previous December total manpower across all classifications.',
    cyeHeadcount: 'CYE Headcount = current December total manpower across all classifications.',
    cyAveHeadcount: 'CY Ave. Headcount = average of Jan-Dec total manpower across all classifications.',
    summaryOpPlan: 'YE uses the configured row YE rule. CY Average uses the Jan-Dec average for the same row.',
    summaryHours: 'YE is the Jan-Dec year total for each calculated hours metric. CY Average is the monthly average of that same total.',
    summaryHeadcount: 'YE / CY Average rollups come from combined driver rows and total manpower across classifications.'
};

function getSummaryHeadcountFormulaText(label) {
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

    return formulaByLabel[label] || 'YE / CY Average rollups come from combined driver rows and total manpower across classifications.';
}

function formatValue(value, valueType) {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    if (valueType === 'text') {
        return String(value);
    }
    if (Number(value) === 0) {
        return '';
    }
    if (valueType === 'percent') {
        return `${Number(value).toLocaleString('en-US', {
            minimumFractionDigits: 1,
            maximumFractionDigits: 1
        })}%`;
    }
    if (valueType === 'decimal') {
        return Number(value).toLocaleString('en-US', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }
    return Number(value).toLocaleString('en-US');
}

function formatCardValue(value, valueType) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) {
        return '0';
    }
    if (valueType === 'percent') {
        return `${numeric.toLocaleString('en-US', {
            minimumFractionDigits: 1,
            maximumFractionDigits: 1
        })}%`;
    }
    if (valueType === 'decimal') {
        return numeric.toLocaleString('en-US', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }
    return numeric.toLocaleString('en-US');
}

function isEmptyMonthValue(value) {
    return value === null || value === undefined || value === '';
}

function isZeroLikeNumericValue(value) {
    return !isEmptyMonthValue(value) && Number(value) === 0;
}

function formatEditableInputValue(value, valueType) {
    if (isEmptyMonthValue(value) || isZeroLikeNumericValue(value)) {
        return '';
    }
    if (valueType === 'decimal') {
        return Number(value).toFixed(2);
    }
    return value;
}

function isSameMonthValue(currentValue, nextValue) {
    if ((isEmptyMonthValue(nextValue) || nextValue === null) && (isEmptyMonthValue(currentValue) || isZeroLikeNumericValue(currentValue))) {
        return true;
    }
    if (isEmptyMonthValue(currentValue) && isEmptyMonthValue(nextValue)) {
        return true;
    }
    return Number(currentValue) === Number(nextValue);
}

function roundValue(value, precision = 1) {
    const numericValue = Number(value);
    if (!Number.isFinite(numericValue)) {
        return null;
    }
    const factor = 10 ** precision;
    return Math.round(numericValue * factor) / factor;
}

function percentToDecimal(value) {
    return isEmptyMonthValue(value) ? 0 : Number(value) / 100;
}

function truncateValue(value, precision = 1) {
    const factor = 10 ** precision;
    return Math.trunc((Number(value) || 0) * factor) / factor;
}

function monthKeysThrough(monthKey) {
    const index = EDITABLE_MONTH_KEYS.indexOf(monthKey);
    return index === -1 ? [] : EDITABLE_MONTH_KEYS.slice(0, index + 1);
}

function sumMonthsThrough(values = {}, monthKey) {
    return monthKeysThrough(monthKey).reduce((total, key) => total + (Number(values?.[key]) || 0), 0);
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

function sumMonths(values = {}) {
    return EDITABLE_MONTH_KEYS.reduce((total, monthKey) => total + (Number(values?.[monthKey]) || 0), 0);
}

function computeAverageMonths(values = {}) {
    if (!EDITABLE_MONTH_KEYS.length) {
        return null;
    }
    return roundValue(sumMonths(values) / EDITABLE_MONTH_KEYS.length, 1);
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

export function buildCumulativeTotalValues(previousDecemberTotal, approvedValues, adjustmentRowsByKey) {
    const nextValues = { prevDec: Number(previousDecemberTotal) || 0 };
    let runningTotal = Number(previousDecemberTotal) || 0;

    EDITABLE_MONTH_KEYS.forEach((monthKey) => {
        const adjustmentTotal = Object.values(adjustmentRowsByKey || {}).reduce(
            (total, rowValues) => total + (Number(rowValues?.[monthKey]) || 0),
            0
        );
        runningTotal += (Number(approvedValues?.[monthKey]) || 0) + adjustmentTotal;
        nextValues[monthKey] = runningTotal;
    });

    return nextValues;
}

export function buildTotalManpowerValues(baseValues, approvedValues, adjustmentRowsByKey) {
    const nextValues = {};
    const previousDecemberTotal = (Number(baseValues?.prevDec) || 0) + (Number(approvedValues?.prevDec) || 0);
    nextValues.prevDec = previousDecemberTotal;
    let runningTotal = previousDecemberTotal;

    EDITABLE_MONTH_KEYS.forEach((monthKey) => {
        const adjustmentTotal = Object.values(adjustmentRowsByKey || {}).reduce(
            (total, rowValues) => total + (Number(rowValues?.[monthKey]) || 0),
            0
        );
        runningTotal += adjustmentTotal;
        nextValues[monthKey] = runningTotal;
    });

    return nextValues;
}

export function buildBaseHeadcountValues(baseValues, approvedValues, adjustmentRowsByKey) {
    const nextValues = { prevDec: Number(baseValues?.prevDec) || 0 };
    let runningTotal = (Number(baseValues?.prevDec) || 0) + (Number(approvedValues?.prevDec) || 0);

    EDITABLE_MONTH_KEYS.forEach((monthKey) => {
        const adjustmentTotal = Object.values(adjustmentRowsByKey || {}).reduce(
            (total, rowValues) => total + (Number(rowValues?.[monthKey]) || 0),
            0
        );
        runningTotal += adjustmentTotal;
        nextValues[monthKey] = runningTotal;
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
    adjustmentRowsByKey = {}
}) {
    const nextValues = {
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
        dec: 0,
        ...currentValues
    };

    if (normalizeSectorKey(sector) !== 'assembly' || classification !== 'OTS') {
        return nextValues;
    }

    const percent = Number(vacationPercent) || 0;
    if (percent <= 0 || !entryMonthKey || !exitMonthKey) {
        return nextValues;
    }

    const totalBeforeVacation = buildVacationCoverageBaseValues(baseValues, adjustmentRowsByKey);
    const entryBase = Number(totalBeforeVacation?.[entryMonthKey]) || 0;
    const seededValue = Math.round(entryBase * (percent / 100));

    if (Object.prototype.hasOwnProperty.call(nextValues, entryMonthKey)) {
        nextValues[entryMonthKey] = seededValue;
    }
    if (Object.prototype.hasOwnProperty.call(nextValues, exitMonthKey)) {
        nextValues[exitMonthKey] = -seededValue;
    }

    return nextValues;
}

function buildVacationCoverageBaseValues(baseValues = {}, adjustmentRowsByKey = {}) {
    const nextValues = {};
    const previousDecemberBase = Number(baseValues?.prevDec) || 0;
    nextValues.prevDec = previousDecemberBase;
    let runningAdjustmentTotal = 0;

    EDITABLE_MONTH_KEYS.forEach((monthKey) => {
        const adjustmentTotal = Object.values(adjustmentRowsByKey || {}).reduce(
            (total, rowValues) => total + (Number(rowValues?.[monthKey]) || 0),
            0
        );
        runningAdjustmentTotal += adjustmentTotal;
        const baseForMonth = isEmptyMonthValue(baseValues?.[monthKey])
            ? previousDecemberBase
            : (Number(baseValues?.[monthKey]) || 0);
        nextValues[monthKey] = baseForMonth + runningAdjustmentTotal;
    });

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
        combinedAbsence: roundValue(combinedAbsence * 100, 1),
        scheduledOvertime: roundValue(scheduledOvertime, 1),
        additionalStraightTime: roundValue(additionalStraightTime, 1),
        stHours: roundValue(stHours, 1),
        nsotHours: roundValue(nsotHours, 1),
        totalHours: roundValue(totalHours, 1)
    };
}

export function buildGpsTotalSotDaysValues(weekendValues = {}, eqSotDaysValues = {}) {
    const values = {};
    MONTH_KEYS.forEach((monthKey) => {
        const weekend = weekendValues?.[monthKey];
        const eqSotDays = eqSotDaysValues?.[monthKey];
        const hasData = !isEmptyMonthValue(weekend) || !isEmptyMonthValue(eqSotDays);
        values[monthKey] = hasData
            ? (Number(weekend) || 0) + (Number(eqSotDays) || 0)
            : null;
    });
    return values;
}

export function buildStampingSotEquivalentDaysTotalValues(productionDaysValues = {}, equivalentSotPercentValues = {}) {
    const values = {};
    MONTH_KEYS.forEach((monthKey) => {
        const productionDaysRaw = productionDaysValues?.[monthKey];
        const equivalentSotPercentRaw = equivalentSotPercentValues?.[monthKey];
        const hasData = !isEmptyMonthValue(productionDaysRaw) || !isEmptyMonthValue(equivalentSotPercentRaw);
        if (!hasData) {
            values[monthKey] = null;
            return;
        }
        const productionDays = Number(productionDaysRaw) || 0;
        const equivalentSotPercent = Number(equivalentSotPercentRaw) || 0;
        values[monthKey] = roundValue(productionDays * (equivalentSotPercent / 100), 1);
    });
    return values;
}

function buildAhpuMonthlyValue(totalHours, denominator, isStamping) {
    const safeDenominator = Number(denominator) || 0;
    if (!safeDenominator) {
        return 0;
    }
    const multiplier = isStamping ? 100 : 1;
    return roundValue(((Number(totalHours) || 0) / safeDenominator) * multiplier, 1);
}

export function getFormulaTextByKey(key) {
    return FORMULA_TEXT_BY_KEY[key] || '';
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

function getFallbackFormulaKeyForFamily(row) {
    const family = normalizeFamilyIdentity(row?.sourceValue || row?.label || row?.driver);
    if (!family) {
        return '';
    }

    const familyToFormulaKey = {
        crews: 'crews',
        'number of crews': 'crews',
        shifts: 'shifts',
        'number of shifts': 'shifts',
        'net/net jph': 'netJph',
        'net / net jph': 'netJph',
        'net jph': 'netJph',
        'paid hours per crew': 'paidHoursPerCrew',
        'available working days / month': 'availableDays',
        'available working days/month': 'availableDays',
        'production working days per month': 'productionDays',
        'production working days/month': 'productionDays',
        'eq sot days': 'eqSotDays',
        'base headcount': 'baseHeadcount',
        'base headcount (non supp, no apprentices)': 'baseHeadcount',
        'approved target': 'approvedTargetChanges',
        'advanced target changes': 'approvedTargetChanges',
        'approved target changes': 'approvedTargetChanges',
        'previous ye approved target changes': 'approvedTargetChanges',
        'total manpower (include target changes)': 'totalManpower',
        'total manpower (incl prev ye approved target changes)': 'totalManpower',
        productivity: 'productivityAdjustment',
        'op plan': 'opPlanAdjustment',
        content: 'contentAdjustment',
        sourcing: 'sourcingAdjustment',
        'other/excess': 'otherExcessAdjustment',
        launch: 'launchAdjustment',
        'mfg opt': 'mfgOptAdjustment',
        arc: 'arcAdjustment',
        mbc: 'arcAdjustment',
        placeholder: 'placeholderAdjustment',
        absenteeism: 'absenteeism',
        'absenteeism %': 'absenteeism',
        'absenteeism % + summer vro %': 'combinedAbsence',
        nsot: 'nsot',
        'nsot % = nsot / (st + sot)': 'nsot',
        'scheduled overtime hours': 'scheduledOvertime',
        'additional straight time hours (downweeks, etc)': 'additionalStraightTime',
        'additional straight time hours adjustment': 'additionalStraightTimeAdjustment',
        'additional st adjustment reason': 'additionalStraightTimeAdjustment',
        "st hours (inc. add'l st hours below)": 'stHours',
        'nsot hours (nsot % = nsot / (st + sot)': 'nsotHours',
        'total hours': 'totalHours',
        'ahpu monthly': 'ahpuMonthly',
        'ahpu ytd': 'ahpuYtd',
        'whpu monthly': 'whpuMonthly',
        'vacation replacement': 'vacationCoverage',
        'vacation coverage': 'vacationCoverage'
    };

    return familyToFormulaKey[family] || '';
}

function getResolvedFormulaText(row) {
    if (!row) {
        return '';
    }
    if (row.formulaTooltip) {
        return row.formulaTooltip;
    }

    const directText = getFormulaTextByKey(row.formulaKey || getBaseFormulaKey(row.key));
    if (directText) {
        return directText;
    }

    const fallbackFormulaKey = getFallbackFormulaKeyForFamily(row);
    return getFormulaTextByKey(fallbackFormulaKey);
}

function getYearTotalHelpText(row, tableName) {
    if (!row || row.valueType === 'text') {
        return '';
    }
    if (row.avgTotalTooltip) {
        return row.avgTotalTooltip;
    }
    if (usesCumulativeAverageHeadcount(row, tableName)) {
        return 'Avg / Total = cumulative average headcount across Jan-Dec running totals.';
    }

    if (row.valueType === 'percent') {
        return 'Avg / Total = average of Jan-Dec values.';
    }
    if (row.formulaKey === 'totalManpower' || normalizeFamilyIdentity(row.sourceValue || row.label || row.driver) === 'total manpower (include target changes)') {
        return 'Avg / Total = average of Jan-Dec values.';
    }
    if (tableName === 'driver' && (isBaseHeadcountFamily(row) || String(row.key || '').startsWith('base-') || String(row.key || '').startsWith('total-'))) {
        return 'Avg / Total = average of Jan-Dec values.';
    }
    if (tableName === 'hours' && row.formulaKey === 'combinedAbsence') {
        return 'Avg / Total = average of Jan-Dec values.';
    }
    return 'Avg / Total = sum of Jan-Dec values.';
}

function usesCumulativeAverageHeadcount(row, tableName) {
    if (tableName !== 'driver' || !row) {
        return false;
    }
    const family = normalizeFamilyIdentity(row.sourceValue || row.label || row.driver);
    if (
        family === 'base headcount (non supp, no apprentices)' ||
        family === 'previous ye approved target changes' ||
        family === 'total manpower (include target changes)'
    ) {
        return false;
    }
    return normalizeRenderText(row.category) === 'headcount' || CUMULATIVE_AVERAGE_HC_FAMILIES.has(family);
}

function isBaseHeadcountFamily(row) {
    const family = normalizeFamilyIdentity(row?.sourceValue || row?.label || row?.driver);
    return family === 'base headcount' || family === 'base headcount (non supp, no apprentices)';
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

export function averageMonths(values) {
    return truncateValue(sumMonths(values) / 12, 1);
}

function cumulativeAverage(values = {}) {
    let runningTotal = 0;
    let monthCount = 0;
    let cumulativeSum = 0;

    EDITABLE_MONTH_KEYS.forEach((monthKey) => {
        runningTotal += Number(values?.[monthKey]) || 0;
        cumulativeSum += runningTotal;
        monthCount += 1;
    });

    return monthCount ? cumulativeSum / monthCount : 0;
}

export default class GwbTargetGenerationWorkbench extends NavigationMixin(LightningElement) {
    @api recordId;
    @api plantAdminPermissionOverride;

    @track header;
    vacationCoverageConfig;
    @track renderedSections = [];
    isLoading = true;
    activeViewTab = 'input';
    selectedClassificationFilter = 'All';
    selectedDriverFilter = 'All';
    canEdit = false;
    statusMessage;
    configurationMessage;
    errorMessage;
    dirtyKeys = new Set();
    baselineSections = [];
    commentRowsByCellKey = {};
    selectedCommentCell = null;
    commentDraft = '';
    commentMenuOpen = false;
    commentMenuStyle = '';
    commentModalOpen = false;
    editingCommentId;
    isSavingComment = false;
    sessionSavedCommentCellKeys = new Set();
    statusModalOpen = false;
    statusOptions = [];
    selectedStatusValue = '';
    isPlantScopedUser = false;
    isPlantAdminLikeUser = false;
    canUpdateStatus = false;
    cloneModalOpen = false;
    selectedCloneVersion = '';
    mScheduleOptions = [];
    draftInputValues = {};
    openSections = {
        nonDriver: true,
        driver: true,
        hours: true
    };

    connectedCallback() {
        this.loadScreen();
    }

    get monthColumns() {
        const budgetYear = Number(this.header?.year);
        const previousYearSuffix = Number.isFinite(budgetYear) ? String(budgetYear - 1).slice(-2) : '26';
        return MONTH_COLUMNS.map((column) => (
            column.key === 'prevDec'
                ? { ...column, label: `DEC'${previousYearSuffix}` }
                : column
        ));
    }

    get disableSave() {
        return !this.canEdit || !this.dirtyKeys.size;
    }

    get disableStatusUpdate() {
        return !this.canUpdateStatus || this.isLoading;
    }

    get disableCreateDraft() {
        return !this.header || this.isLoading || this.targetStatus === 'Published' || this.targetStatus === 'Locked';
    }

    get disableCloneConfirm() {
        return this.isLoading || !this.selectedCloneVersion;
    }

    get readyForPublishDisabled() {
        return !this.showStandardHeaderActions || this.isLoading || this.targetStatus !== 'Finance Approved';
    }

    get disableStatusUpdateSave() {
        return this.isLoading || !this.selectedStatusValue;
    }

    get showStatusUpdateAction() {
        return this.canUpdateStatus;
    }

    get isTargetSplitPersona() {
        return this.isPlantAdminLikeUser;
    }

    get isTargetSplitMode() {
        return this.isTargetSplitPersona && this.isTargetSplitScopedStatus;
    }

    get showStandardHeaderActions() {
        return !!this.header && !this.isTargetSplitMode;
    }

    get showCloneButton() {
        return this.showStandardHeaderActions;
    }

    get disableCommentSave() {
        return this.isSavingComment || !this.selectedCommentCell || !this.commentDraft.trim();
    }

    get hasSelectedCommentCell() {
        return !!this.selectedCommentCell;
    }

    get showJustificationActionInContextMenu() {
        return !!this.selectedCommentCell?.supportsJustification;
    }

    get commentMenuPrimaryActionLabel() {
        return this.selectedCommentCell?.tableName === 'hoursJustification'
            ? 'Add or View Reason'
            : 'Add or View Comments';
    }

    get justificationMenuActionLabel() {
        if (!this.selectedCommentCell?.supportsJustification) {
            return 'Add Reason';
        }
        const existingReason = this.selectedCommentCell?.monthKey
            ? this.getExistingAdditionalStReason(this.selectedCommentCell.monthKey)
            : null;
        return existingReason ? 'Edit Reason' : 'Add Reason';
    }

    get selectedCellComments() {
        if (!this.selectedCommentCell) {
            return [];
        }
        return this.getCommentsForCell(
            this.selectedCommentCell.tableName,
            this.selectedCommentCell.rowKey,
            this.selectedCommentCell.monthKey
        );
    }

    get hasSelectedCellComments() {
        return this.selectedCellComments.length > 0;
    }

    get selectedCommentContextItems() {
        if (!this.selectedCommentCell) {
            return [];
        }
        const items = [
            {
                key: 'area',
                label: 'Area',
                value:
                    this.selectedCommentCell.tableName === 'hoursJustification'
                        ? 'Hours Reason'
                        : this.selectedCommentCell.sectionName || this.selectedCommentCell.tableName
            },
            {
                key: 'month',
                label: 'Month',
                value: this.selectedCommentCell.monthLabel || this.selectedCommentCell.monthKey
            }
        ];
        if (this.selectedCommentCell.classification && this.selectedCommentCell.classification !== 'Shared') {
            items.push({
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

    get commentActivityTitle() {
        return this.selectedCommentCell?.tableName === 'hoursJustification'
            ? 'Reason for this month'
            : 'Comments for this cell';
    }

    get commentInputLabel() {
        return this.selectedCommentCell?.tableName === 'hoursJustification'
            ? 'Reason'
            : 'Comment';
    }

    get commentInputPlaceholder() {
        return this.selectedCommentCell?.tableName === 'hoursJustification'
            ? 'Add the required reason for this month.'
            : 'Add a short note for this value.';
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

    get commentModalTitle() {
        if (!this.selectedCommentCell) {
            return 'Cell comments';
        }
        return `${this.selectedCommentCell.rowLabel} · ${this.selectedCommentCell.monthLabel || this.selectedCommentCell.monthKey}`;
    }

    get isEditingExistingComment() {
        return !!this.editingCommentId;
    }

    get commentPanelEmptyText() {
        if (!this.canEdit) {
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
        return !!this.selectedCommentCell && this.canEdit;
    }

    get hasActiveBudget() {
        return !!this.header;
    }

    get targetPageTitle() {
        const formulaTitle = (this.header?.targetTitle || '').trim();
        if (formulaTitle) {
            return formulaTitle;
        }

        const plant = this.header?.plantName || 'Target';
        const targetVersion = formatTargetVersion(
            this.header?.version,
            this.header?.year,
            this.header?.mScheduleVersion
        );
        const sectorKey = normalizeSectorKey(this.header?.sector);
        if (sectorKey === 'gps') {
            const productType = (this.header?.productType || '').trim();
            const plantProgramName = (this.header?.plantProgramName || '').trim();
            const functionalArea = (this.header?.functionalArea || '').trim();
            const partType = (this.header?.partType || '').trim();
            const gpsQualifier = functionalArea || partType;
            const qualifierAndVersion = [gpsQualifier, targetVersion].filter(Boolean).join(' ');
            return [plant, productType, plantProgramName, qualifierAndVersion].filter(Boolean).join(' - ');
        }
        return targetVersion ? `${plant} - ${targetVersion}` : plant;
    }

    get targetRegion() {
        return this.header?.region || 'GMNA';
    }

    get targetPlant() {
        return this.header?.plantName || '—';
    }

    get targetSector() {
        return this.header?.sector || '—';
    }

    get targetMSchedule() {
        return this.header?.mScheduleVersion || '—';
    }

    get targetStatus() {
        return this.header?.status || '';
    }

    handleAdjustmentStatusChange(event) {
        const nextStatus = event.detail?.status;
        if (!nextStatus || !this.header) {
            return;
        }

        this.header = {
            ...this.header,
            status: nextStatus
        };
        this.normalizeActiveViewTab();
    }

    get cloneActionGroupVisible() {
        return this.showStandardHeaderActions || this.showStatusUpdateAction;
    }

    get resolvedPlantAdminPermission() {
        return typeof this.plantAdminPermissionOverride === 'boolean'
            ? this.plantAdminPermissionOverride
            : this.isPlantAdminLikeUser || hasPlantAdminPermission;
    }

    get isPlantAdminReviewMode() {
        return this.resolvedPlantAdminPermission &&
            this.targetStatus === 'Plant Review' &&
            normalizeSectorKey(this.header?.sector) !== 'gps';
    }

    isBaseEditAllowedByStatus() {
        const status = String(this.targetStatus || '').trim();
        if (!this.recordId) {
            return false;
        }
        if (status === 'Published' || status === 'Locked') {
            return false;
        }
        if (this.resolvedPlantAdminPermission && status === 'Plant Review Complete') {
            return false;
        }
        return true;
    }

    resolveStatusMessage(serverMessage) {
        const status = String(this.targetStatus || '').trim();
        if (status === 'Published') {
            return 'Target rows are read-only when the target status is Published.';
        }
        if (status === 'Locked') {
            return 'Target rows are read-only when the target status is Locked.';
        }
        if (this.resolvedPlantAdminPermission && status === 'Plant Review Complete') {
            return 'Target rows are read-only when the target status is Plant Review Complete.';
        }
        return serverMessage || null;
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
        (this.headcountSection?.rows || []).forEach((row) => {
            if (!row?.label) {
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
            labels.add(row.label);
        });
        return Array.from(labels).map((label) => ({ label, value: label }));
    }

    get selectedKpiClassifications() {
        const selectedClassification = String(this.selectedClassificationFilter || 'All').trim();
        if (selectedClassification === 'OTS' || selectedClassification === 'Skilled' || selectedClassification === 'Salaried') {
            return [selectedClassification];
        }
        return ['OTS', 'Skilled', 'Salaried'];
    }

    get selectedKpiClassificationLabel() {
        return this.selectedKpiClassifications.length === 1 ? this.selectedKpiClassifications[0] : '';
    }

    get selectedKpiClassificationSuffix() {
        return this.selectedKpiClassificationLabel ? ` (${this.selectedKpiClassificationLabel})` : '';
    }

    get nonDriverOpen() {
        return !!this.openSections.nonDriver;
    }

    get driverOpen() {
        return !!this.openSections.driver;
    }

    get hoursOpen() {
        return !!this.openSections.hours;
    }

    get nonDriverSectionToggleLabel() {
        return this.nonDriverOpen ? 'Collapse' : 'Expand';
    }

    get driverSectionToggleLabel() {
        return this.driverOpen ? 'Collapse' : 'Expand';
    }

    get hoursSectionToggleLabel() {
        return this.hoursOpen ? 'Collapse' : 'Expand';
    }

    get opPlanSection() {
        return this.renderedSections.find((section) => this.getSectionTableName(section.name) === 'nonDriver') || null;
    }

    get headcountSection() {
        return this.renderedSections.find((section) => this.getSectionTableName(section.name) === 'driver') || null;
    }

    get hoursSection() {
        return this.renderedSections.find((section) => this.getSectionTableName(section.name) === 'hours') || null;
    }

    get showNonDriverSection() {
        return !!this.opPlanSection;
    }

    get showDriverSection() {
        return !!this.headcountSection;
    }

    get showHoursSection() {
        return !!this.hoursSection;
    }

    get nonDriverRenderRows() {
        const rows = (this.opPlanSection?.rows || []).filter((row) => this.matchesFilter(row));
        return this.buildInputRows(rows, 'nonDriver');
    }

    get driverRenderRows() {
        const rows = (this.headcountSection?.rows || []).filter((row) => this.matchesFilter(row));
        return this.buildInputRows(rows, 'driver');
    }

    get hourCalculationRows() {
        const rows = (this.hoursSection?.rows || []).filter((row) => this.matchesFilter(row));
        const rowsWithJustification = rows.filter((row) => row.key !== ADDITIONAL_ST_REASON_ROW_KEY);
        const justificationRow = this.buildAdditionalStraightJustificationRow(rows);
        if (justificationRow && this.matchesFilter(justificationRow)) {
            rowsWithJustification.push(justificationRow);
        }
        return this.buildInputRows(rowsWithJustification, 'hours');
    }

    get kpiTiles() {
        const rowMap = this.getRenderedRowMap();
        const scheduled = sumMonths(rowMap.get('scheduledVolume')?.values || {});
        const calculated = sumMonths(rowMap.get('calcVolume')?.values || {});
        const variance = scheduled - calculated;
        const variancePct = scheduled ? (variance / scheduled) * 100 : 0;
        const availableDays = sumMonths(rowMap.get('availableDays')?.values || {});
        const productionDays = sumMonths(rowMap.get('productionDays')?.values || {});
        const eqSotDays = sumMonths(rowMap.get('eqSotDays')?.values || {});
        const stampingEquivalentDays = sumMonths(rowMap.get('stampingSotEquivalentDaysTotal')?.values || {});
        const isStampingSector = normalizeSectorKey(this.header?.sector) === 'stamping';
        return [
            {
                key: 'calcVolume',
                label: 'Calculated Volume incl. SOT days',
                value: formatCardValue(calculated, 'number'),
                formulaText: getFormulaTextByKey('calcVolume'),
                className: 'kpi-card'
            },
            {
                key: 'scheduledVolume',
                label: 'Scheduled Volume',
                value: formatCardValue(scheduled, 'number'),
                formulaText: getFormulaTextByKey('scheduledVolume'),
                className: 'kpi-card'
            },
            {
                key: 'volumeVariance',
                label: 'Scheduled Volume minus Calculated Volume',
                value: formatCardValue(variance, 'number'),
                formulaText: getFormulaTextByKey('volumeVariance'),
                className: variance < 0 ? 'kpi-card kpi-card_alert' : 'kpi-card'
            },
            {
                key: 'variancePct',
                label: 'Scheduled Volume Variance',
                value: formatCardValue(roundValue(variancePct, 1), 'percent'),
                formulaText: 'Scheduled Volume Variance = (Scheduled Volume minus Calculated Volume) / Scheduled Volume',
                className: variancePct < 0 ? 'kpi-card kpi-card_alert' : 'kpi-card'
            },
            {
                key: 'availableDays',
                label: 'Available Working Days / Month',
                value: formatCardValue(availableDays, 'decimal'),
                formulaText: 'Year total = Jan-Dec sum of Available Working Days / Month.',
                className: 'kpi-card'
            },
            {
                key: 'productionDays',
                label: 'Production Working Days / Month',
                value: formatCardValue(productionDays, 'decimal'),
                formulaText: 'Year total = Jan-Dec sum of Production Working Days / Month.',
                className: 'kpi-card'
            },
            {
                key: isStampingSector ? 'stampingSotEquivalentDaysTotal' : 'eqSotDays',
                label: isStampingSector ? 'SOT equivalent days total' : 'EQ SOT Days',
                value: formatCardValue(isStampingSector ? stampingEquivalentDays : eqSotDays, 'decimal'),
                formulaText: isStampingSector
                    ? getFormulaTextByKey('stampingSotEquivalentDaysTotal')
                    : 'Year total = Jan-Dec sum of EQ SOT Days.',
                className: 'kpi-card'
            }
        ];
    }

    get manpowerKpiTiles() {
        const rowMap = this.getRenderedRowMap();
        const selectedClassifications = this.selectedKpiClassifications;
        const productivity = this.sumRowsForClassifications(rowMap, 'prod', selectedClassifications);
        const mbc = this.sumRowsForClassifications(rowMap, 'mbc', selectedClassifications);
        const lms = this.sumRowsForClassifications(rowMap, 'lms', selectedClassifications);
        const totalManpowerMonthlyValues = this.buildTotalManpowerMonthlyValues(rowMap, selectedClassifications);
        const previousYearTotal = Number(totalManpowerMonthlyValues.prevDec) || 0;
        const productivityPercent = previousYearTotal ? ((productivity + mbc + lms) / previousYearTotal) * 100 : 0;

        return [
            {
                key: 'productivityPercent',
                label: `Productivity %${this.selectedKpiClassificationSuffix}`,
                value: formatCardValue(roundValue(productivityPercent, 1), 'percent'),
                formulaText: getFormulaTextByKey('prodPct'),
                className: 'kpi-card'
            },
            {
                key: 'totalHeadcountAverage',
                label: `Total Headcount Current Year Avg${this.selectedKpiClassificationSuffix}`,
                value: formatCardValue(computeAverageMonths(totalManpowerMonthlyValues), 'number'),
                formulaText: getFormulaTextByKey('totalManpower'),
                className: 'kpi-card'
            }
        ];
    }

    get hoursKpiTiles() {
        const rowMap = this.getRenderedRowMap();
        const selectedClassifications = this.selectedKpiClassifications;
        const stValues = this.buildCalculatedHoursSummaryValues(rowMap, 'stHours', selectedClassifications);
        const scheduledOvertimeValues = this.buildCalculatedHoursSummaryValues(rowMap, 'scheduledOvertime', selectedClassifications);
        const nsotValues = this.buildCalculatedHoursSummaryValues(rowMap, 'nsotHours', selectedClassifications);
        const additionalStraightValues = this.buildCalculatedHoursSummaryValues(rowMap, 'additionalStraightTime', selectedClassifications);
        const totalHoursValues = this.buildCalculatedHoursSummaryValues(rowMap, 'totalHours', selectedClassifications);
        const allSt = sumMonths(stValues);
        const allSot = sumMonths(scheduledOvertimeValues);
        const allNsot = sumMonths(nsotValues);
        const allAdditionalStraightTime = sumMonths(additionalStraightValues);
        const allTotalHours = sumMonths(totalHoursValues);
        const nsotCyPct = allSt + allSot === 0 ? 0 : (allNsot / (allSt + allSot)) * 100;
        const sotCyPct = allSt === 0 ? 0 : (allSot / allSt) * 100;
        return [
            {
                key: 'stHours',
                label: `ST Hours (inc. Add'l ST Hours)${this.selectedKpiClassificationSuffix}`,
                value: formatCardValue(roundValue(allSt, 1), 'decimal'),
                formulaText: getFormulaTextByKey('stHoursTile'),
                className: 'kpi-card'
            },
            {
                key: 'nsotHours',
                label: `NSOT Hours${this.selectedKpiClassificationSuffix}`,
                value: formatCardValue(roundValue(allNsot, 1), 'decimal'),
                formulaText: getFormulaTextByKey('nsotHoursTile'),
                className: 'kpi-card'
            },
            {
                key: 'nsotCyPct',
                label: `NSOT CY %${this.selectedKpiClassificationSuffix}`,
                value: formatCardValue(roundValue(nsotCyPct, 1), 'percent'),
                formulaText: getFormulaTextByKey('nsotCyPct'),
                className: 'kpi-card'
            },
            {
                key: 'sotCyPct',
                label: `SOT CY %${this.selectedKpiClassificationSuffix}`,
                value: formatCardValue(roundValue(sotCyPct, 1), 'percent'),
                formulaText: getFormulaTextByKey('sotCyPct'),
                className: 'kpi-card'
            },
            {
                key: 'additionalSt',
                label: `Additional ST Hours${this.selectedKpiClassificationSuffix}`,
                value: formatCardValue(roundValue(allAdditionalStraightTime, 1), 'decimal'),
                formulaText: getFormulaTextByKey('additionalSt'),
                className: 'kpi-card'
            },
            {
                key: 'totalHours',
                label: `Total Hours${this.selectedKpiClassificationSuffix}`,
                value: formatCardValue(roundValue(allTotalHours, 1), 'decimal'),
                formulaText: getFormulaTextByKey('totalHoursTile'),
                className: 'kpi-card'
            }
        ];
    }

    get summaryRows() {
        const rowMap = this.getRenderedRowMap();
        const rows = [
            this.buildSummaryRow(rowMap, 'scheduledVolume', 'Scheduled Volume', 'sum'),
            this.buildSummaryRow(rowMap, 'calcVolume', 'Calculated Volume', 'sum'),
            this.buildSummaryRow(rowMap, 'volumeVariance', 'Volume Variance', 'sum'),
            this.buildSummaryRow(rowMap, 'total-ots', 'Total Manpower (OTS)', 'avg'),
            this.buildSummaryRow(rowMap, 'total-skilled', 'Total Manpower (Skilled)', 'avg'),
            this.buildSummaryRow(rowMap, 'total-salaried', 'Total Manpower (Salaried)', 'avg'),
            this.buildSummaryRow(rowMap, 'totalHours-all', 'Total Hours', 'sum'),
            this.buildSummaryRow(rowMap, 'stHours-all', 'ST Hours', 'sum'),
            this.buildSummaryRow(rowMap, 'nsotHours-all', 'NSOT Hours', 'sum'),
            this.buildSummaryRow(rowMap, 'scheduledOvertime-all', 'Scheduled Overtime Hours', 'sum'),
            this.buildSummaryRow(rowMap, 'additionalStraightTime-all', 'Additional ST Hours', 'sum')
        ];
        return rows.filter(Boolean);
    }

    get comparisonRows() {
        const rowMap = this.getRenderedRowMap();
        const rows = [
            this.buildComparisonRow(rowMap, 'scheduledVolume', 'Scheduled Volume'),
            this.buildComparisonRow(rowMap, 'calcVolume', 'Calculated Volume'),
            this.buildComparisonRow(rowMap, 'volumeVariance', 'Volume Variance'),
            this.buildComparisonRow(rowMap, 'total-ots', 'Total Manpower (OTS)'),
            this.buildComparisonRow(rowMap, 'total-skilled', 'Total Manpower (Skilled)'),
            this.buildComparisonRow(rowMap, 'total-salaried', 'Total Manpower (Salaried)'),
            this.buildComparisonRow(rowMap, 'totalHours-all', 'Total Hours')
        ];
        return rows.filter(Boolean);
    }

    get hasSummaryRows() {
        return this.summaryRows.length > 0;
    }

    get hasComparisonRows() {
        return this.comparisonRows.length > 0;
    }

    get summaryCurrentYearLabel() {
        return String(this.header?.year || '');
    }

    get summaryPreviousYearLabel() {
        const currentYear = Number(this.summaryCurrentYearLabel);
        return Number.isFinite(currentYear) ? String(currentYear - 1) : '';
    }

    get summaryHeroCards() {
        const rowMap = this.getRenderedRowMap();
        const totalManpowerMonthlyValues = this.buildTotalManpowerMonthlyValues(rowMap);
        const productivitySummaryPct = this.calculateProductivitySummaryPct(rowMap);
        return [
            {
                key: 'pyeHeadcount',
                label: 'PYE Headcount',
                year: this.summaryPreviousYearLabel,
                value: formatCardValue(totalManpowerMonthlyValues.prevDec, 'number'),
                formulaText: getFormulaTextByKey('pyeHeadcount'),
                className: 'summary-total-card'
            },
            {
                key: 'cyeHeadcount',
                label: 'CYE Headcount',
                year: this.summaryCurrentYearLabel,
                value: formatCardValue(totalManpowerMonthlyValues.dec, 'number'),
                formulaText: getFormulaTextByKey('cyeHeadcount'),
                className: 'summary-total-card'
            },
            {
                key: 'cyAveHeadcount',
                label: 'CY Ave. Headcount',
                year: this.summaryCurrentYearLabel,
                value: formatCardValue(computeAverageMonths(totalManpowerMonthlyValues), 'number'),
                formulaText: getFormulaTextByKey('cyAveHeadcount'),
                className: 'summary-total-card'
            },
            {
                key: 'cyProductivity',
                label: 'CY % Productivity',
                year: this.summaryCurrentYearLabel,
                value: formatCardValue(roundValue(productivitySummaryPct, 1), 'percent'),
                formulaText: getFormulaTextByKey('prodPct'),
                className: productivitySummaryPct < 0 ? 'summary-total-card summary-total-card_alert' : 'summary-total-card'
            }
        ];
    }

    get summaryOpPlanRows() {
        const rowMap = this.getRenderedRowMap();
        const rows = [
            this.buildSummaryMetricRowFromRow(rowMap, 'crews', 'Crews', 'number', 'dec', 'YE = December value. CY Average = Jan-Dec average.'),
            this.buildSummaryMetricRowFromRow(rowMap, 'shifts', 'Shifts', 'number', 'dec', 'YE = December value. CY Average = Jan-Dec average.'),
            this.buildSummaryMetricRowFromRow(rowMap, 'netJph', 'Net/Net JPH', 'decimal', 'dec', 'YE = December value. CY Average = Jan-Dec average.'),
            this.buildSummaryMetricRowFromRow(rowMap, 'productionDays', 'Production Days', 'decimal', 'dec', 'YE = December value. CY Average = Jan-Dec average.'),
            this.buildSummaryMetricRowFromRow(rowMap, 'eqSotDays', 'EQ SOT Days', 'decimal', 'dec', 'YE = December value. CY Average = Jan-Dec average.'),
            this.buildSummaryMetricRowFromRow(rowMap, 'scheduledVolume', 'Scheduled Volume', 'number', 'sum', getFormulaTextByKey('summaryOpPlan'))
        ].filter(Boolean);
        const stampingStrokes = rowMap.get('stampingScheduledVolumeStrokes');
        if (stampingStrokes) {
            rows.push(this.buildSummaryMetricRowFromValues('summary-stamping-strokes', 'Stamping Strokes', stampingStrokes.values, 'number', 'sum', getFormulaTextByKey('summaryOpPlan')));
        }
        return rows;
    }

    get summaryHoursRows() {
        const rowMap = this.getRenderedRowMap();
        const stValues = this.buildCalculatedHoursSummaryValues(rowMap, 'stHours');
        const scheduledOvertimeValues = this.buildCalculatedHoursSummaryValues(rowMap, 'scheduledOvertime');
        const nsotValues = this.buildCalculatedHoursSummaryValues(rowMap, 'nsotHours');
        const totalHoursValues = this.buildCalculatedHoursSummaryValues(rowMap, 'totalHours');
        const nsotPctValues = this.buildNsotSummaryPercentValues(stValues, scheduledOvertimeValues, nsotValues);
        return [
            this.buildSummaryMetricRowFromValues('st-hours-summary', 'ST', stValues, 'decimal', 'sum', getFormulaTextByKey('stHours')),
            this.buildSummaryMetricRowFromValues('scheduled-overtime-summary', 'SOT', scheduledOvertimeValues, 'decimal', 'sum', getFormulaTextByKey('scheduledOvertime')),
            this.buildSummaryMetricRowFromValues('nsot-hours-summary', 'NSOT', nsotValues, 'decimal', 'sum', getFormulaTextByKey('nsotHours')),
            this.buildSummaryMetricRowFromValues('nsot-pct-summary', '%NSOT', nsotPctValues, 'percent', 'avg', getFormulaTextByKey('nsotCyPct')),
            this.buildSummaryMetricRowFromValues('total-hours-summary', 'Total Hours', totalHoursValues, 'decimal', 'sum', getFormulaTextByKey('totalHours'))
        ].filter(Boolean);
    }

    get summaryHeadcountRows() {
        const rowMap = this.getRenderedRowMap();
        const totalManpowerMonthlyValues = this.buildTotalManpowerMonthlyValues(rowMap);
        const productivitySummaryPct = this.calculateProductivitySummaryPct(rowMap);
        return [
            this.buildSummaryMetricRowFromValues('summary-ye-target', 'YE Target', this.buildCombinedRowValues(rowMap, ['base-ots', 'base-skilled', 'base-salaried']), 'number', 'prevDec', getSummaryHeadcountFormulaText('YE Target')),
            this.buildSummaryMetricRowFromValues('summary-productivity-all-in', 'Productivity (all in)', this.buildCombinedDriverFamilyValues(rowMap, ['productivity', 'arc', 'lms']), 'number', 'dec', getSummaryHeadcountFormulaText('Productivity (all in)')),
            this.buildSummaryMetricRowFromValues('summary-op-plan-changes', 'Op Plan Changes', this.buildCombinedDriverFamilyValues(rowMap, ['op plan']), 'number', 'dec', getSummaryHeadcountFormulaText('Op Plan Changes')),
            this.buildSummaryMetricRowFromValues('summary-vacation-coverage', 'Vacation Coverage', this.buildCombinedDriverFamilyValues(rowMap, ['vacation replacement']), 'number', 'dec', getSummaryHeadcountFormulaText('Vacation Coverage')),
            this.buildSummaryMetricRowFromValues('summary-content-changes', 'Content Changes', this.buildCombinedDriverFamilyValues(rowMap, ['content']), 'number', 'dec', getSummaryHeadcountFormulaText('Content Changes')),
            this.buildSummaryMetricRowFromValues('summary-sourcing', 'Sourcing', this.buildCombinedDriverFamilyValues(rowMap, ['sourcing']), 'number', 'dec', getSummaryHeadcountFormulaText('Sourcing')),
            this.buildSummaryMetricRowFromValues('summary-others', 'Others', this.buildCombinedDriverFamilyValues(rowMap, ['other/excess']), 'number', 'dec', getSummaryHeadcountFormulaText('Others')),
            this.buildSummaryMetricRowFromValues('summary-mfg-op', 'Mfg Op', this.buildCombinedDriverFamilyValues(rowMap, ['mfg opt']), 'number', 'dec', getSummaryHeadcountFormulaText('Mfg Op')),
            this.buildSummaryMetricRowFromValues('summary-ye-total', 'YE Total', totalManpowerMonthlyValues, 'number', 'dec', getSummaryHeadcountFormulaText('YE Total')),
            this.buildSummaryMetricRowFromValues('summary-cy-ave', 'CY Ave.', totalManpowerMonthlyValues, 'number', 'avg', getSummaryHeadcountFormulaText('CY Ave.')),
            this.buildSummaryPercentRow('summary-prod-pct', '% Prod.', productivitySummaryPct, getFormulaTextByKey('prodPct'))
        ].filter(Boolean);
    }

    get showNoConfigurationMessage() {
        return !this.isLoading && !this.renderedSections.length && !!this.configurationMessage;
    }

    get isInputTab() {
        return this.activeViewTab === 'input';
    }

    get isSummaryTab() {
        return this.activeViewTab === 'summary';
    }

    get isAdjustmentsTab() {
        return this.showAdjustmentsTab && this.activeViewTab === 'adjustments';
    }

    get inputTabClass() {
        return this.activeViewTab === 'input' ? 'workbench-tab workbench-tab_active' : 'workbench-tab';
    }

    get summaryTabClass() {
        return this.activeViewTab === 'summary' ? 'workbench-tab workbench-tab_active' : 'workbench-tab';
    }

    get adjustmentsTabClass() {
        return this.activeViewTab === 'adjustments' ? 'workbench-tab workbench-tab_active' : 'workbench-tab';
    }

    get isTargetSplitScopedStatus() {
        return this.targetStatus === 'Published' || this.targetStatus === 'Locked';
    }

    get showAdjustmentsTab() {
        return this.isTargetSplitScopedStatus;
    }

    async loadScreen() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const response = await getBudgetScreen({ gwbYearId: this.recordId });
            this.header = response?.header;
            this.isPlantAdminLikeUser = response?.isPlantAdminLikeUser === true;
            this.isPlantScopedUser = response?.isPlantScopedUser === true;
            this.canUpdateStatus = response?.canUpdateStatus === true;
            this.statusOptions = (response?.statusOptions || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.selectedStatusValue = '';
            this.canEdit = response?.canEdit === true && this.isBaseEditAllowedByStatus();
            this.statusMessage = this.resolveStatusMessage(response?.statusMessage || null);
            this.configurationMessage = response?.configurationMessage || null;
            this.vacationCoverageConfig = response?.vacationCoverageConfig || null;
            this.commentRowsByCellKey = {};
            this.sessionSavedCommentCellKeys = new Set();
            this.selectedCommentCell = null;
            this.commentDraft = '';
            this.commentMenuOpen = false;
            this.commentModalOpen = false;
            this.editingCommentId = null;
            this.draftInputValues = {};
            (response?.comments || []).forEach((comment) => this.addCommentToState(comment));
            this.baselineSections = this.decorateSections(response?.sections || []);
            this.renderedSections = deepClone(this.baselineSections);
            this.applyDerivedRows();
            this.markCalculatedRowsForSync();
            this.normalizeActiveViewTab();
            if (!this.mScheduleOptions.length && this.showCloneButton) {
                await this.loadMScheduleOptions();
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load dynamic target screen.';
        } finally {
            this.isLoading = false;
        }
    }

    decorateSections(sections) {
        return (sections || []).map((section) => ({
            ...section,
            rows: (section.rows || []).map((row) => ({
                ...row,
                isEditableInUi: this.isRowEditableInUi(row),
                isCommentableInUi: this.isRowCommentableInUi(row),
                monthCells: MONTH_COLUMNS.map((column) => ({
                    key: `${row.key}-${column.key}`,
                    monthKey: column.key,
                    displayValue: formatValue(row.values?.[column.key], row.valueType),
                    value: row.values?.[column.key],
                    inputClass: ''
                }))
            }))
        }));
    }

    applyDerivedRows() {
        const nextSections = deepClone(this.renderedSections);
        const rowMap = new Map();
        nextSections.forEach((section) => {
            section.rows.forEach((row) => {
                if (this.isPreviousYearApprovedTargetRow(row)) {
                    this.clearEditableMonthValues(row);
                }
                rowMap.set(row.key, row);
            });
        });

        this.applyApprovedTargetBaseHeadcountDelta(rowMap);
        this.applyStructuralDerivedRows(rowMap);
        this.applyHourDerivedRows(rowMap);

        nextSections.forEach((section) => {
            section.rows = section.rows.map((row) => ({
                ...row,
                isEditableInUi: this.isRowEditableInUi(row),
                isCommentableInUi: this.isRowCommentableInUi(row),
                monthCells: this.buildMonthCells(row, section.name)
            }));
        });

        this.renderedSections = nextSections;
    }

    clearEditableMonthValues(row) {
        if (!row?.values) {
            return;
        }
        EDITABLE_MONTH_KEYS.forEach((monthKey) => {
            row.values[monthKey] = null;
        });
    }

    applyApprovedTargetBaseHeadcountDelta(rowMap) {
        ['OTS', 'Skilled', 'Salaried'].forEach((classification) => {
            const suffix = classificationSuffix(classification);
            const baseRow = rowMap.get(`base-${suffix}`);
            const approvedRow = rowMap.get(`advanced-${suffix}`);
            if (!baseRow || !approvedRow) {
                return;
            }

            const adjustmentRowsByKey = this.getHeadcountDriverAdjustmentRows(rowMap, suffix);

            baseRow.values = buildBaseHeadcountValues(
                baseRow.values || {},
                approvedRow.values || {},
                adjustmentRowsByKey
            );
        });
    }

    buildMonthCells(row, sectionName) {
        const tableName = this.getSectionTableName(sectionName);
        const isTextDisplayRow = row.valueType === 'text';
        const isAdditionalStJustificationRow = row.key === ADDITIONAL_ST_REASON_ROW_KEY;
        const isJustificationDisplayRow = isTextDisplayRow || isAdditionalStJustificationRow;
        const commentRowKey = isAdditionalStJustificationRow ? ADDITIONAL_ST_REASON_ROW_KEY : this.getCommentRowKeyForDisplayRow(row);
        const commentTableName = isJustificationDisplayRow ? 'hoursJustification' : tableName;
        return MONTH_COLUMNS.map((column) => ({
            key: `${row.key}-${column.key}`,
            monthKey: column.key,
            displayValue: formatValue(row.values?.[column.key], row.valueType),
            value: row.values?.[column.key],
            inputClass: this.dirtyKeys.has(`${row.key}:${column.key}`) ? 'edited-cell' : '',
            tableName: commentTableName,
            rowKey: commentRowKey,
            rowLabel: row.label,
            classification: row.classification,
            sectionName,
            cellKey: this.getGridCellKey(commentTableName, commentRowKey, column.key),
            commentCount: this.getCellCommentCount(commentTableName, commentRowKey, column.key),
            commentIconClass: isAdditionalStJustificationRow && this.getExistingAdditionalStReason(column.key)
                ? 'cell-comment-icon cell-comment-icon_existing'
                : this.getCommentIconClass(commentTableName, commentRowKey, column.key),
            commentable: isJustificationDisplayRow ? column.key !== 'prevDec' : row.isCommentableInUi,
            hasReasonIndicator: isAdditionalStJustificationRow && !!this.getExistingAdditionalStReason(column.key),
            vacationMarker: this.getVacationMarker(row, column.key),
            supportsJustification:
                (ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(row.key) || isAdditionalStJustificationRow) &&
                (tableName === 'hours' || tableName === 'driver' || commentTableName === 'hoursJustification') &&
                column.key !== 'prevDec'
        }));
    }

    getVacationMarker(row, monthKey) {
        if (!this.vacationCoverageConfig || !row || monthKey === 'prevDec') {
            return null;
        }
        const isVacationRow = row.key === 'vac-ots' && classificationSuffix(row.classification) === 'ots';
        if (!isVacationRow) {
            return null;
        }
        if (monthKey === this.vacationCoverageConfig.entryMonthKey) {
            return {
                label: 'Entry',
                className: 'vacation-marker vacation-marker_entry'
            };
        }
        if (monthKey === this.vacationCoverageConfig.exitMonthKey) {
            return {
                label: 'Exit',
                className: 'vacation-marker vacation-marker_exit'
            };
        }
        return null;
    }

    buildAdditionalStraightJustificationRow(rows = []) {
        const adjustmentRows = (rows || []).filter((row) => ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(row.key));
        if (!adjustmentRows.length) {
            return null;
        }
        const existingMetadataRow = (rows || []).find((row) => row.key === ADDITIONAL_ST_REASON_ROW_KEY);

        const values = { prevDec: '' };
        EDITABLE_MONTH_KEYS.forEach((monthKey) => {
            const existingReason = this.getExistingAdditionalStReason(monthKey);
            const hasAdjustments = adjustmentRows.some((row) => (Number(row.values?.[monthKey]) || 0) !== 0);
            values[monthKey] = existingReason ? '' : (hasAdjustments ? 'Required' : '');
        });

        const row = {
            ...existingMetadataRow,
            key: ADDITIONAL_ST_REASON_ROW_KEY,
            category: existingMetadataRow?.category || this.hoursSection?.name || 'Hours',
            label: existingMetadataRow?.label || 'Additional ST Adjustment Reason',
            sourceValue: existingMetadataRow?.sourceValue || 'Additional ST Adjustment Reason',
            classification: 'Shared',
            sourceType: existingMetadataRow?.sourceType || 'Parameter',
            lineType: 'Input',
            sequence: existingMetadataRow?.sequence || 32,
            valueType: 'text',
            editable: false,
            formulaKey: existingMetadataRow?.formulaKey || 'additionalStraightTimeAdjustment',
            values
        };
        row.isEditableInUi = false;
        row.isCommentableInUi = true;
        row.monthCells = this.buildMonthCells(row, this.hoursSection?.name || 'Hours');
        return row;
    }

    getDraftInputKey(sectionName, rowKey, monthKey) {
        return `${sectionName || 'unknown'}:${rowKey || 'unknown'}:${monthKey || 'unknown'}`;
    }

    getDraftInputValue(sectionName, rowKey, monthKey) {
        return this.draftInputValues[this.getDraftInputKey(sectionName, rowKey, monthKey)];
    }

    setDraftInputValue(sectionName, rowKey, monthKey, value) {
        this.draftInputValues = {
            ...this.draftInputValues,
            [this.getDraftInputKey(sectionName, rowKey, monthKey)]: value
        };
    }

    clearDraftInputValue(sectionName, rowKey, monthKey) {
        const key = this.getDraftInputKey(sectionName, rowKey, monthKey);
        if (!(key in this.draftInputValues)) {
            return;
        }
        const nextDrafts = { ...this.draftInputValues };
        delete nextDrafts[key];
        this.draftInputValues = nextDrafts;
    }

    sanitizeDraftInputValue(rawValue, valueType = 'number') {
        const normalized = String(rawValue ?? '');
        if (valueType === 'text') {
            return normalized;
        }

        if (normalized === '' || normalized === '-' || normalized === '+' || normalized === '.' || normalized === '-.' || normalized === '+.') {
            return normalized;
        }

        const numericMatch = normalized.match(/^([+-]?\d*)(?:\.(\d*))?$/);
        if (!numericMatch) {
            return normalized.replace(/[^0-9.+-]/g, '');
        }

        const sign = normalized.startsWith('-') ? '-' : normalized.startsWith('+') ? '+' : '';
        const integerPortion = numericMatch[1] || '';
        const decimalPortion = numericMatch[2];
        const safeInteger = integerPortion.replace(/[+-]/g, '');

        if (valueType === 'number') {
            return `${sign}${safeInteger}`;
        }

        return decimalPortion !== undefined
            ? `${sign}${safeInteger}.${decimalPortion}`
            : `${sign}${safeInteger}`;
    }

    normalizeInputValue(rawValue, eventType = 'change', valueType = 'number') {
        const normalized = String(rawValue ?? '').trim();
        const isInputEvent = eventType === 'input';
        if (isInputEvent && ['', '-', '+', '.', '-.', '+.'].includes(normalized)) {
            return null;
        }
        if (normalized === '') {
            return null;
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

    isRowEditableInUi(row) {
        const baseEditable = row?.editable && this.canEdit;
        if (!baseEditable) {
            return false;
        }
        if (this.isPlantAdminReviewMode) {
            return ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(row?.key);
        }
        return true;
    }

    isRowCommentableInUi(row) {
        const baseEditable = row?.editable && this.canEdit;
        return !!baseEditable;
    }

    handleCancel() {
        this.renderedSections = deepClone(this.baselineSections);
        this.dirtyKeys = new Set();
        this.commentMenuOpen = false;
        this.applyDerivedRows();
    }

    handleOpenStatusModal() {
        if (this.disableStatusUpdate) {
            return;
        }
        this.errorMessage = null;
        this.selectedStatusValue = this.statusOptions.length === 1
            ? this.statusOptions[0].value
            : '';
        this.statusModalOpen = true;
    }

    handleCloseStatusModal() {
        this.statusModalOpen = false;
        this.selectedStatusValue = '';
    }

    async loadMScheduleOptions() {
        try {
            const options = await getMScheduleOptions();
            this.mScheduleOptions = (options || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
        } catch (error) {
            this.mScheduleOptions = [];
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load M-Schedule options.';
        }
    }

    handleStatusValueChange(event) {
        this.selectedStatusValue = event.detail.value || '';
    }

    async handleSaveStatusUpdate() {
        if (this.disableStatusUpdateSave) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = null;
        this.statusMessage = null;
        const requestedStatus = this.selectedStatusValue;
        try {
            const updatedHeader = await updateTargetStatus({
                gwbYearId: this.recordId,
                nextStatus: requestedStatus
            });
            this.statusModalOpen = false;
            await this.loadScreen();
            const updatedStatus = updatedHeader?.status || requestedStatus;
            this.header = {
                ...(this.header || {}),
                ...(updatedHeader || {}),
                status: updatedStatus
            };
            this.canEdit = this.canEdit && this.isBaseEditAllowedByStatus();
            this.normalizeActiveViewTab();
            this.statusMessage = `Status updated to ${updatedStatus}.`;
            this.showToast('Status updated', this.statusMessage, 'success');
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to update target status.';
            this.showToast('Status update failed', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleCreateDraft() {
        if (this.disableCreateDraft) {
            return;
        }
        this.errorMessage = null;
        this.selectedCloneVersion = '';
        if (!this.mScheduleOptions.length) {
            await this.loadMScheduleOptions();
        }
        this.cloneModalOpen = true;
    }

    handleCloseCloneModal() {
        this.cloneModalOpen = false;
        this.selectedCloneVersion = '';
    }

    handleCloneVersionChange(event) {
        this.selectedCloneVersion = event.detail.value || '';
    }

    async handleConfirmCreateDraft() {
        if (this.disableCloneConfirm || !this.recordId) {
            return;
        }

        const selectedVersion = String(this.selectedCloneVersion || '').replace('%2B', '+');
        const currentVersion = String(this.header?.mScheduleVersion || this.header?.version || '').replace('%2B', '+');
        if (selectedVersion && currentVersion && selectedVersion === currentVersion) {
            this.errorMessage = 'The selected M-Schedule is the same as the source target. Choose a different M-Schedule to clone.';
            return;
        }

        this.isLoading = true;
        this.errorMessage = null;
        this.statusMessage = null;
        try {
            const result = await cloneDraftTargets({
                targetIds: [this.recordId],
                versionValue: this.selectedCloneVersion
            });
            this.handleCloseCloneModal();
            const clonedTargetId = result?.clonedTargetIds?.[0];
            if (clonedTargetId) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: clonedTargetId,
                        objectApiName: 'GWB_Year__c',
                        actionName: 'view'
                    }
                });
                return;
            }
            this.statusMessage = 'Target cloned successfully.';
            this.showToast('Target cloned', this.statusMessage, 'success');
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to clone target.';
            this.showToast('Clone failed', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleReadyForPublish() {
        if (this.readyForPublishDisabled || !this.recordId) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = null;
        this.statusMessage = null;
        try {
            const result = await publishSelectedTargets({ targetIds: [this.recordId] });
            await this.loadScreen();
            if ((result?.updatedCount || 0) > 0) {
                this.header = {
                    ...(this.header || {}),
                    status: 'Published'
                };
                this.canEdit = false;
                this.normalizeActiveViewTab();
                await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
                this.statusMessage = 'Status updated to Published.';
                this.showToast('Status updated', this.statusMessage, 'success');
            } else {
                this.statusMessage = 'Status was not updated. Target must be in Finance Approved status before publishing.';
                this.showToast('Status not updated', this.statusMessage, 'warning');
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to publish target.';
            this.showToast('Publish failed', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleInputChange(event) {
        if (!this.canEdit) {
            return;
        }
        const rowKey = event.target.dataset.rowKey;
        const sectionName = event.target.dataset.sectionName;
        const monthKey = event.target.dataset.monthKey;
        const rawValue = event.detail?.value ?? event.target.value;
        const currentRow = this.findRenderedRow(sectionName, rowKey);
        const valueType = currentRow?.valueType || 'number';
        const sanitizedValue = this.sanitizeDraftInputValue(rawValue, valueType);
        if (event.target.value !== sanitizedValue) {
            event.target.value = sanitizedValue;
        }
        if (event.type === 'input') {
            this.setDraftInputValue(sectionName, rowKey, monthKey, sanitizedValue);
            return;
        }

        this.clearDraftInputValue(sectionName, rowKey, monthKey);
        const value = this.normalizeInputValue(sanitizedValue, event.type, valueType);
        if (value === null && sanitizedValue !== '') {
            return;
        }
        if (isSameMonthValue(currentRow?.values?.[monthKey], value)) {
            this.clearDraftInputValue(sectionName, rowKey, monthKey);
            return;
        }
        const fillForwardOnEdit = currentRow?.fillForwardOnEdit;
        const targetMonthIndex = MONTH_KEYS.indexOf(monthKey);
        const isApprovedPreviousDecemberEdit = monthKey === 'prevDec' && this.isPreviousYearApprovedTargetRow(currentRow);
        const monthKeysToUpdate = isApprovedPreviousDecemberEdit
            ? [monthKey]
            : !fillForwardOnEdit || targetMonthIndex === -1
            ? [monthKey]
            : MONTH_KEYS.slice(targetMonthIndex);

        this.renderedSections = this.renderedSections.map((section) => {
            if (section.name !== sectionName) {
                return section;
            }
            return {
                ...section,
                rows: section.rows.map((row) => {
                    if (row.key !== rowKey) {
                        return row;
                    }
                    const nextValues = {
                        ...(row.values || {})
                    };
                    monthKeysToUpdate.forEach((editableMonthKey) => {
                        nextValues[editableMonthKey] =
                            editableMonthKey === 'prevDec' && !this.isPreviousYearApprovedTargetRow(row)
                                ? row.values?.[editableMonthKey]
                                : value;
                    });
                    return {
                        ...row,
                        values: nextValues
                    };
                })
            };
        });
        monthKeysToUpdate.forEach((editableMonthKey) => {
            if (editableMonthKey !== 'prevDec' || isApprovedPreviousDecemberEdit) {
                this.dirtyKeys.add(`${rowKey}:${editableMonthKey}`);
            }
        });
        this.applyDerivedRows();
    }

    syncVisibleInputsToState() {
        const visibleInputs = [...this.template.querySelectorAll('input.grid-input')];
        if (!visibleInputs.length) {
            return;
        }

        let hasCommittedChange = false;
        visibleInputs.forEach((inputToSync) => {
            const rowKey = inputToSync.dataset.rowKey;
            const sectionName = inputToSync.dataset.sectionName;
            const monthKey = inputToSync.dataset.monthKey;
            if (!rowKey || !sectionName || !monthKey) {
                return;
            }

            const currentRow = this.findRenderedRow(sectionName, rowKey);
            if (!currentRow) {
                return;
            }

            const valueType = currentRow.valueType || 'number';
            const sanitizedValue = this.sanitizeDraftInputValue(inputToSync.value, valueType);
            const value = this.normalizeInputValue(sanitizedValue, 'change', valueType);
            if (value === null && sanitizedValue !== '') {
                return;
            }
            if (isSameMonthValue(currentRow.values?.[monthKey], value)) {
                this.clearDraftInputValue(sectionName, rowKey, monthKey);
                return;
            }

            const fillForwardOnEdit = currentRow.fillForwardOnEdit;
            const targetMonthIndex = MONTH_KEYS.indexOf(monthKey);
            const isApprovedPreviousDecemberEdit = monthKey === 'prevDec' && this.isPreviousYearApprovedTargetRow(currentRow);
            const monthKeysToUpdate = isApprovedPreviousDecemberEdit
                ? [monthKey]
                : !fillForwardOnEdit || targetMonthIndex === -1
                ? [monthKey]
                : MONTH_KEYS.slice(targetMonthIndex);

            this.renderedSections = this.renderedSections.map((section) => {
                if (section.name !== sectionName) {
                    return section;
                }
                return {
                    ...section,
                    rows: section.rows.map((row) => {
                        if (row.key !== rowKey) {
                            return row;
                        }
                        const nextValues = {
                            ...(row.values || {})
                        };
                        monthKeysToUpdate.forEach((editableMonthKey) => {
                            nextValues[editableMonthKey] =
                                editableMonthKey === 'prevDec' && !this.isPreviousYearApprovedTargetRow(row)
                                    ? row.values?.[editableMonthKey]
                                    : value;
                        });
                        return {
                            ...row,
                            values: nextValues
                        };
                    })
                };
            });

            monthKeysToUpdate.forEach((editableMonthKey) => {
                if (editableMonthKey !== 'prevDec' || isApprovedPreviousDecemberEdit) {
                    this.dirtyKeys.add(`${rowKey}:${editableMonthKey}`);
                }
            });
            this.clearDraftInputValue(sectionName, rowKey, monthKey);
            hasCommittedChange = true;
        });

        if (hasCommittedChange) {
            this.applyDerivedRows();
        }
    }

    async handleSave() {
        if (!this.canEdit) {
            return;
        }
        this.syncVisibleInputsToState();
        this.applyDerivedRows();
        const missingReasons = this.getMissingAdditionalStReasons();
        if (missingReasons.length) {
            this.errorMessage = `Reason... · ${[...new Set(missingReasons)].join(', ')}`;
            this.showToast('Reason required', this.errorMessage, 'warning');
            return;
        }
        const rowsToSave = [];
        this.renderedSections.forEach((section) => {
            section.rows.forEach((row) => {
                const isPersistedTotalRow = String(row.lineType || '').trim().toLowerCase() === 'total';
                const isPersistedDerivedRow = this.isPersistableDerivedRow(row);
                const isPersistedSourceRow = this.isPersistableSourceRow(row);
                if (!row.editable && !isPersistedTotalRow && !isPersistedDerivedRow && !isPersistedSourceRow && row.formulaKey !== 'totalManpower') {
                    return;
                }
                if (this.isPlantAdminReviewMode && !ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(row.key)) {
                    return;
                }
                rowsToSave.push({
                    key: row.key,
                    label: row.label,
                    sourceValue: row.sourceValue,
                    category: row.category,
                    classification: row.classification,
                    sourceType: row.sourceType,
                    sourceSection: row.sourceSection,
                    lineType: row.lineType,
                    sequence: row.sequence,
                    valueType: row.valueType,
                    editable: row.editable,
                    formulaKey: row.formulaKey,
                    recordId: row.recordId,
                    values: row.values
                });
            });
        });
        if (!this.isPlantAdminReviewMode) {
            rowsToSave.push(this.buildProductivityPercentPersistenceRow());
        }

        this.isLoading = true;
        this.errorMessage = null;
        this.statusMessage = null;
        try {
            const saveResponse = await saveBudgetRows({ gwbYearId: this.recordId, rows: rowsToSave });
            if (!saveResponse?.savedRecordCount) {
                return;
            }
            this.statusMessage = 'Changes saved successfully.';
            this.showToast('Saved', this.statusMessage, 'success');
            this.dirtyKeys = new Set();
            this.baselineSections = deepClone(this.renderedSections);
            this.applyDerivedRows();
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to save dynamic target screen.';
            this.statusMessage = null;
            this.showToast('Save failed', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    isPersistableDerivedRow(row) {
        if (row?.sourceType !== 'Derived') {
            return false;
        }
        const lineType = String(row.lineType || '').trim().toLowerCase();
        return lineType === 'formula' || lineType === 'total' || Boolean(row.formulaKey);
    }

    isPersistableSourceRow(row) {
        if (!row || String(row.valueType || '').trim().toLowerCase() === 'text') {
            return false;
        }
        return row.sourceType === 'Parameter' || row.sourceType === 'Driver';
    }

    buildProductivityPercentPersistenceRow() {
        const productivityPercent = roundValue(this.calculateProductivitySummaryPct(this.getRenderedRowMap()), 1);
        return {
            key: 'summary-prod-pct',
            label: '% Prod.',
            sourceValue: '% Prod.',
            category: 'Headcount',
            classification: 'Total',
            sourceType: 'Derived',
            sourceSection: 'Manpower',
            lineType: 'Total',
            sequence: 999,
            valueType: 'percent',
            editable: false,
            formulaKey: 'prodPct',
            recordId: null,
            values: { dec: productivityPercent }
        };
    }

    markCalculatedRowsForSync() {
        const baselineRowsByKey = new Map();
        (this.baselineSections || []).forEach((section) => {
            (section.rows || []).forEach((row) => baselineRowsByKey.set(row.key, row));
        });

        (this.renderedSections || []).forEach((section) => {
            (section.rows || []).forEach((row) => {
                const isPersistedTotalRow = String(row.lineType || '').trim().toLowerCase() === 'total';
                const isPersistedDerivedRow = this.isPersistableDerivedRow(row);
                const isPersistedSourceRow = this.isPersistableSourceRow(row);
                if (!isPersistedTotalRow && !isPersistedDerivedRow && !isPersistedSourceRow && row.formulaKey !== 'totalManpower') {
                    return;
                }

                const baselineRow = baselineRowsByKey.get(row.key);
                MONTH_KEYS.forEach((monthKey) => {
                    if (!isSameMonthValue(baselineRow?.values?.[monthKey], row.values?.[monthKey])) {
                        this.dirtyKeys.add(`${row.key}:${monthKey}`);
                    }
                });
            });
        });
    }

    findRenderedRow(sectionName, rowKey) {
        const section = this.renderedSections.find((candidate) => candidate.name === sectionName);
        return section?.rows?.find((candidate) => candidate.key === rowKey) || null;
    }

    getRenderedRowMap() {
        const rowMap = new Map();
        this.renderedSections.forEach((section) => {
            (section.rows || []).forEach((row) => rowMap.set(row.key, row));
        });
        return rowMap;
    }

    getBaselineRowMap() {
        const rowMap = new Map();
        this.baselineSections.forEach((section) => {
            (section.rows || []).forEach((row) => rowMap.set(row.key, row));
        });
        return rowMap;
    }

    getSectionTableName(sectionName) {
        const normalized = String(sectionName || '').toLowerCase();
        if (normalized.includes('op plan')) {
            return 'nonDriver';
        }
        if (normalized.includes('headcount')) {
            return 'driver';
        }
        if (normalized.includes('non-driver')) {
            return 'nonDriver';
        }
        if (normalized.includes('driver')) {
            return 'driver';
        }
        if (normalized.includes('hour')) {
            return 'hours';
        }
        if (normalized.includes('summary with comparison')) {
            return 'comparison';
        }
        if (normalized.includes('summary')) {
            return 'summary';
        }
        return 'dynamic';
    }

    buildInputRows(rows, tableName) {
        const list = this.sortRowsForRender(this.dedupeRowsForRender(rows || []));
        if (tableName !== 'driver' && tableName !== 'hours') {
            return list.map((row, index) => this.buildPreparedInputRow(row, tableName, index + 1, index));
        }

        const familyRows = this.buildCollapsedRenderFamilies(list);
        const groupedRows = [];
        let currentRowNumber = 1;
        familyRows.forEach((groupedFamilyRows) => {
            const orderedFamilyRows = [...groupedFamilyRows].sort((left, right) => {
                const sequenceDelta = (Number(left?.sequence) || 0) - (Number(right?.sequence) || 0);
                if (sequenceDelta !== 0) {
                    return sequenceDelta;
                }
                return classificationSortRank(left?.classification) - classificationSortRank(right?.classification);
            });
            const rowSpan = orderedFamilyRows.length;
            const renderIndexStart = groupedRows.length;
            const groupFormulaText = this.getSharedGroupedFormulaText(orderedFamilyRows);
            for (let rowIndex = 0; rowIndex < orderedFamilyRows.length; rowIndex += 1) {
                groupedRows.push(
                    this.buildPreparedInputRow(
                        orderedFamilyRows[rowIndex],
                        tableName,
                        currentRowNumber,
                        renderIndexStart + rowIndex,
                        rowIndex === 0,
                        rowSpan,
                        rowIndex === (orderedFamilyRows.length - 1),
                        groupFormulaText
                    )
                );
            }
            currentRowNumber += 1;
        });
        return groupedRows;
    }

    buildCollapsedRenderFamilies(rows) {
        const familyMap = new Map();
        (rows || []).forEach((row) => {
            const groupKey = this.getDriverGroupKey(row);
            if (!familyMap.has(groupKey)) {
                familyMap.set(groupKey, {
                    sequence: Number(row?.sequence) || 0,
                    rowsByClassification: new Map(),
                    labels: new Map()
                });
            }

            const family = familyMap.get(groupKey);
            family.sequence = Math.min(family.sequence, Number(row?.sequence) || 0);
            family.labels.set(this.getFamilyLabelPreferenceKey(row), row?.label || '');

            const classificationKey = normalizeRenderText(row?.classification);
            const existing = family.rowsByClassification.get(classificationKey);
            if (!existing || this.shouldPreferRenderRow(row, existing)) {
                family.rowsByClassification.set(classificationKey, row);
            }
        });

        return [...familyMap.entries()]
            .sort((left, right) => {
                const sequenceDelta = (left[1]?.sequence || 0) - (right[1]?.sequence || 0);
                if (sequenceDelta !== 0) {
                    return sequenceDelta;
                }
                return left[0].localeCompare(right[0]);
            })
            .map(([, family]) => {
                const familyLabel = this.resolveFamilyLabel(family);
                return [...family.rowsByClassification.values()].map((row) => ({
                    ...row,
                    familyLabel
                }));
            });
    }

    getSharedGroupedFormulaText(rows) {
        const formulaTexts = [...new Set((rows || [])
            .filter((row) => classificationSuffix(row?.classification) !== 'total')
            .map((row) => getResolvedFormulaText(row))
            .filter((text) => !!text))];
        return formulaTexts.length === 1 ? formulaTexts[0] : '';
    }

    getFamilyLabelPreferenceKey(row) {
        const label = String(row?.label || '');
        return `${label.length}`.padStart(4, '0');
    }

    resolveFamilyLabel(family) {
        const labels = [...(family?.labels?.values() || [])].filter(Boolean);
        if (!labels.length) {
            return '';
        }
        return labels.sort((left, right) => right.length - left.length || left.localeCompare(right))[0];
    }

    shouldPreferRenderRow(candidate, existing) {
        const candidateHasRecord = Boolean(candidate?.recordId);
        const existingHasRecord = Boolean(existing?.recordId);
        if (candidateHasRecord !== existingHasRecord) {
            return candidateHasRecord;
        }

        const candidateIsTotal = String(candidate?.lineType || '').trim().toLowerCase() === 'total';
        const existingIsTotal = String(existing?.lineType || '').trim().toLowerCase() === 'total';
        if (candidateIsTotal !== existingIsTotal) {
            return candidateIsTotal;
        }

        const candidateSequence = Number(candidate?.sequence) || 0;
        const existingSequence = Number(existing?.sequence) || 0;
        if (candidateSequence !== existingSequence) {
            return candidateSequence < existingSequence;
        }

        return String(candidate?.key || '').localeCompare(String(existing?.key || '')) < 0;
    }

    matchesFilter(row) {
        const selectedClassification = this.selectedClassificationFilter;
        const selectedDriver = this.selectedDriverFilter;
        const rowClassification = row?.classification || '';
        const rowDriver = row?.label || '';

        if (selectedClassification !== 'All' && rowClassification && rowClassification !== selectedClassification) {
            return false;
        }
        if (selectedDriver !== 'All' && rowDriver && rowDriver !== selectedDriver) {
            return false;
        }
        return true;
    }

    dedupeRowsForRender(rows) {
        const seen = new Set();
        return (rows || []).filter((row) => {
            const signature = [
                normalizeRenderText(row?.category),
                normalizeRenderText(row?.label),
                normalizeRenderText(row?.classification),
                normalizeRenderText(row?.sourceType)
            ].join('|');
            if (seen.has(signature)) {
                return false;
            }
            seen.add(signature);
            return true;
        });
    }

    sortRowsForRender(rows) {
        return [...(rows || [])].sort((left, right) => {
            const sequenceDelta = (Number(left?.sequence) || 0) - (Number(right?.sequence) || 0);
            if (sequenceDelta !== 0) {
                return sequenceDelta;
            }

            const classificationDelta = classificationSortRank(left?.classification) - classificationSortRank(right?.classification);
            if (classificationDelta !== 0) {
                return classificationDelta;
            }

            return String(left?.label || '').localeCompare(String(right?.label || ''));
        });
    }

    getDriverGroupKey(row) {
        return [
            normalizeRenderText(row?.category),
            normalizeFamilyIdentity(row?.sourceValue || row?.label || row?.driver)
        ].join('|');
    }

    buildPreparedInputRow(
        row,
        tableName,
        rowNumber,
        index,
        showDriverGroup = true,
        driverRowSpan = 1,
        isGroupEnd = false,
        groupFormulaText = ''
    ) {
        const summaryValue = this.calculateRowSummary(row, tableName);
        const formulaText = getResolvedFormulaText(row);
        const isGroupedClassificationTable = tableName === 'driver' || tableName === 'hours';
        const isTotalClassification = classificationSuffix(row?.classification) === 'total';
        const showGroupedFormulaText = isGroupedClassificationTable && showDriverGroup && groupFormulaText;
        return {
            ...row,
            renderKey: `${row?.key || 'row'}-${index}-${row?.classification || 'shared'}`,
            rowNumber,
            displayRowNumber: rowNumber,
            showDriverGroup,
            driverRowSpan,
            driver: row.familyLabel || row.label || row.driver || row.sourceValue,
            formulaText: isGroupedClassificationTable ? groupFormulaText : formulaText,
            classificationFormulaText: '',
            yearTotalFormulaText: getYearTotalHelpText(row, tableName),
            classificationClass: `cell-classification ${this.getClassificationClassSuffix(row.classification)}`,
            rowClass: `${this.buildGridRowClass(row)} ${isGroupEnd ? 'driver-group-divider' : ''}`.trim(),
            summaryValue,
            totalClassificationFormulaText: '',
            cells: (row.monthCells || []).map((cell) => this.buildInputCell(cell, row))
        };
    }

    buildInputCell(cell, row) {
        const hasComments = cell.commentCount > 0;
        const hasPendingComment = this.isPendingCommentCell(cell.tableName, cell.rowKey, cell.monthKey);
        const hasSessionComment = this.sessionSavedCommentCellKeys.has(cell.cellKey);
        const hasJustification = !!cell.hasJustification;
        const hasReasonIndicator = !!cell.hasReasonIndicator;
        const showCommentState = hasComments || hasPendingComment || hasSessionComment || hasJustification || hasReasonIndicator;
        const draftInputValue = this.getDraftInputValue(cell.sectionName, row.key, cell.monthKey);
        return {
            ...cell,
            inputValue:
                draftInputValue !== undefined
                    ? draftInputValue
                    : formatEditableInputValue(cell.value, row.valueType),
            inputStep: row.valueType === 'decimal' || row.valueType === 'percent' ? '0.1' : '1',
            editable: this.isCellEditableInUi(row, cell),
            showCommentIndicator: showCommentState,
            hasComments: hasComments || hasReasonIndicator,
            commentButtonClass: showCommentState ? 'cell-comment-btn cell-comment-btn_visible' : 'cell-comment-btn cell-comment-btn_hidden',
            cellClass: this.buildGridCellClass(row, cell)
        };
    }

    isCellEditableInUi(row, cell) {
        if (!row?.isEditableInUi || !cell) {
            return false;
        }

        if (this.isVacationEntryExitCell(row, cell.monthKey)) {
            return false;
        }

        if (this.isPreviousYearApprovedTargetRow(row)) {
            return cell.monthKey === 'prevDec';
        }

        return cell.monthKey !== 'prevDec';
    }

    isVacationEntryExitCell(row, monthKey) {
        if (!this.vacationCoverageConfig || !row || !monthKey || monthKey === 'prevDec') {
            return false;
        }
        if (this.getVacationMarker(row, monthKey)) {
            return true;
        }
        const rowFamily = normalizeFamilyIdentity(row.sourceValue || row.label || row.driver);
        const isVacationRow =
            classificationSuffix(row.classification) === 'ots' &&
            (row.key === 'vac-ots' ||
                rowFamily === 'vacation replacement' ||
                rowFamily === 'vacation coverage');
        return (
            isVacationRow &&
            (monthKey === this.vacationCoverageConfig.entryMonthKey ||
                monthKey === this.vacationCoverageConfig.exitMonthKey)
        );
    }

    isPreviousYearApprovedTargetRow(row) {
        const normalizedLabel = normalizeFamilyIdentity(row?.sourceValue || row?.label || row?.driver);
        return normalizedLabel === 'previous ye approved target changes';
    }

    calculateRowSummary(row, tableName) {
        if (this.isPreviousYearApprovedTargetRow(row)) {
            return '';
        }
        const values = row.values || {};
        let result;
        if (usesCumulativeAverageHeadcount(row, tableName)) {
            result = cumulativeAverage(values);
        } else if (row.valueType === 'percent') {
            result = computeAverageMonths(values);
        } else if (row.formulaKey === 'totalManpower' || normalizeFamilyIdentity(row.sourceValue || row.label || row.driver) === 'total manpower (include target changes)') {
            result = computeAverageMonths(values);
        } else if (tableName === 'driver' && (isBaseHeadcountFamily(row) || row.key.startsWith('base-') || row.key.startsWith('total-'))) {
            result = computeAverageMonths(values);
        } else if (tableName === 'hours' && row.formulaKey === 'combinedAbsence') {
            result = computeAverageMonths(values);
        } else {
            result = sumMonths(values);
        }
        return formatValue(result, row.valueType);
    }

    buildGridRowClass(row) {
        const classes = [];
        const classification = classificationSuffix(row.classification);
        if (classification && classification !== 'total') {
            classes.push(`grid-row_${classification}`);
        }
        if (!row.isEditableInUi) {
            classes.push('grid-row_readonly');
        }
        return classes.join(' ');
    }

    buildGridCellClass(row, cell) {
        const classes = ['grid-cell'];
        if (cell.monthKey === 'prevDec') {
            classes.push('grid-cell_prev');
        }
        if (!row.isEditableInUi) {
            classes.push('grid-cell_calculated');
        }
        if (row.valueType === 'text' || row.key === ADDITIONAL_ST_REASON_ROW_KEY) {
            classes.push('grid-cell_text-display');
        }
        const classification = classificationSuffix(row.classification);
        if (classification && classification !== 'total') {
            classes.push(`grid-cell_${classification}`);
        }
        const hasSavedComment = this.getCellCommentCount(cell.tableName, cell.rowKey, cell.monthKey) > 0;
        const isPendingComment = this.isPendingCommentCell(cell.tableName, cell.rowKey, cell.monthKey);
        const isSessionComment = this.sessionSavedCommentCellKeys.has(cell.cellKey);
        if (isPendingComment) {
            classes.push('grid-cell_comment-pending');
        } else if (isSessionComment) {
            classes.push('grid-cell_comment-session');
        } else if (hasSavedComment) {
            classes.push('grid-cell_comment-existing');
        }
        return classes.join(' ');
    }

    getClassificationClassSuffix(classification) {
        const suffix = classificationSuffix(classification);
        return suffix ? `classification-text_${suffix}` : '';
    }

    buildTotalManpowerMonthlyValues(rowMap = this.getRenderedRowMap(), classifications = ['OTS', 'Skilled', 'Salaried']) {
        return MONTH_KEYS.reduce((values, monthKey) => {
            values[monthKey] = this.sumRowMonthForClassifications(rowMap, 'total', classifications, monthKey);
            return values;
        }, {});
    }

    calculateProductivitySummaryPct(rowMap = this.getRenderedRowMap(), classifications = ['OTS', 'Skilled', 'Salaried']) {
        const productivityAdjustmentTotal =
            this.sumRowsForClassifications(rowMap, 'prod', classifications) +
            this.sumRowsForClassifications(rowMap, 'mbc', classifications) +
            this.sumRowsForClassifications(rowMap, 'lms', classifications);
        const priorYearTotalManpower = Number(this.buildTotalManpowerMonthlyValues(rowMap, classifications).prevDec) || 0;
        return priorYearTotalManpower === 0 ? 0 : (productivityAdjustmentTotal / priorYearTotalManpower) * 100;
    }

    sumRowsForClassifications(rowMap, rowPrefix, classifications = ['OTS', 'Skilled', 'Salaried']) {
        return (classifications || []).reduce(
            (total, classification) => total + sumMonths(rowMap.get(`${rowPrefix}-${classificationSuffix(classification)}`)?.values || {}),
            0
        );
    }

    sumRowMonthForClassifications(rowMap, rowPrefix, classifications = ['OTS', 'Skilled', 'Salaried'], monthKey) {
        return (classifications || []).reduce(
            (total, classification) => total + (Number(rowMap.get(`${rowPrefix}-${classificationSuffix(classification)}`)?.values?.[monthKey]) || 0),
            0
        );
    }

    buildCombinedRowValues(rowMap, rowKeys = []) {
        return MONTH_KEYS.reduce((values, monthKey) => {
            values[monthKey] = rowKeys.reduce(
                (total, rowKey) => total + (Number(rowMap.get(rowKey)?.values?.[monthKey]) || 0),
                0
            );
            return values;
        }, {});
    }

    buildCombinedDriverFamilyValues(rowMap, familyNames = []) {
        const familySet = new Set((familyNames || []).map((family) => normalizeFamilyIdentity(family)));
        return MONTH_KEYS.reduce((values, monthKey) => {
            let total = 0;
            rowMap.forEach((row) => {
                if (!this.isHeadcountDriverRow(row)) {
                    return;
                }
                const rowFamily = normalizeFamilyIdentity(row.sourceValue || row.label || row.driver);
                if (familySet.has(rowFamily)) {
                    total += Number(row.values?.[monthKey]) || 0;
                }
            });
            values[monthKey] = total;
            return values;
        }, {});
    }

    getHeadcountDriverAdjustmentRows(rowMap, classificationSuffixValue) {
        const adjustmentRowsByKey = {};
        rowMap.forEach((row) => {
            if (!this.isHeadcountDriverRow(row)) {
                return;
            }
            if (classificationSuffix(row.classification) !== classificationSuffixValue) {
                return;
            }
            adjustmentRowsByKey[row.key] = row.values || {};
        });
        return adjustmentRowsByKey;
    }

    isHeadcountDriverRow(row) {
        if (!row || row.sourceType !== 'Driver') {
            return false;
        }
        const category = normalizeFamilyIdentity(row.category);
        const section = normalizeFamilyIdentity(row.sourceSection);
        const family = normalizeFamilyIdentity(row.sourceValue || row.label || row.driver);
        return category === 'headcount' ||
            section === 'headcount' ||
            section === 'manpower' ||
            CUMULATIVE_AVERAGE_HC_FAMILIES.has(family);
    }

    buildSummarySheetRows(definitions) {
        const rowMap = this.getRenderedRowMap();
        return definitions.map((definition) => {
            const row = rowMap.get(definition.key);
            if (!row) {
                return null;
            }
            const yearEndValue = definition.mode === 'sum'
                ? sumMonths(row.values || {})
                : row.values?.dec;
            return {
                key: definition.key,
                label: definition.label,
                yearEnd: formatValue(yearEndValue, row.valueType),
                average: formatValue(computeAverageMonths(row.values || {}), row.valueType),
                formulaText: definition.formulaKey
                    ? getFormulaTextByKey(definition.formulaKey)
                    : getResolvedFormulaText(row)
            };
        }).filter(Boolean);
    }

    buildSummaryMetricRowFromRow(rowMap, rowKey, label, valueType, mode = 'sum', formulaText = '') {
        const row = rowMap.get(rowKey);
        if (!row) {
            return null;
        }
        return this.buildSummaryMetricRowFromValues(`summary-${rowKey}`, label, row.values || {}, valueType || row.valueType, mode, formulaText || getResolvedFormulaText(row));
    }

    buildSummaryMetricRowFromValues(key, label, values = {}, valueType, mode = 'sum', formulaText = '') {
        let yearEndValue;
        if (mode === 'sum') {
            yearEndValue = sumMonths(values || {});
        } else if (mode === 'avg') {
            yearEndValue = computeAverageMonths(values || {});
        } else if (mode === 'prevDec') {
            yearEndValue = values?.prevDec;
        } else {
            yearEndValue = values?.dec;
        }
        const averageValue = computeAverageMonths(values || {});
        return {
            key,
            label,
            yearEnd: formatValue(yearEndValue, valueType),
            average: formatValue(averageValue, valueType),
            formulaText
        };
    }

    buildSummaryPercentRow(key, label, value, formulaText = '') {
        const numericValue = Number(value) || 0;
        return {
            key,
            label,
            yearEnd: formatValue(numericValue, 'percent'),
            average: formatValue(numericValue, 'percent'),
            formulaText
        };
    }

    buildCalculatedHoursSummaryValues(rowMap, metricKey, classifications = ['OTS', 'Skilled', 'Salaried']) {
        return MONTH_KEYS.reduce((values, monthKey) => {
            values[monthKey] = (classifications || []).reduce(
                (total, classification) => total + (Number(this.calculateHoursForMonth(rowMap, classification, monthKey)[metricKey]) || 0),
                0
            );
            return values;
        }, {});
    }

    buildNsotSummaryPercentValues(stValues = {}, scheduledOvertimeValues = {}, nsotValues = {}) {
        return MONTH_KEYS.reduce((values, monthKey) => {
            const denominator = (Number(stValues?.[monthKey]) || 0) + (Number(scheduledOvertimeValues?.[monthKey]) || 0);
            values[monthKey] = denominator === 0 ? 0 : roundValue(((Number(nsotValues?.[monthKey]) || 0) / denominator) * 100, 1);
            return values;
        }, {});
    }

    getGridCellKey(tableName, rowKey, monthKey) {
        return `${tableName || 'unknown'}:${rowKey || 'unknown'}:${monthKey || 'unknown'}`;
    }

    getLegacyCompatibleCommentRowKey(rowKey) {
        return COMMENT_ROW_KEY_ALIASES[rowKey] || rowKey;
    }

    getCommentRowKeyForDisplayRow(row) {
        if (!row) {
            return '';
        }
        const directKey = this.getLegacyCompatibleCommentRowKey(row.key);
        if (directKey !== row.key) {
            return directKey;
        }

        const family = normalizeFamilyIdentity(row.sourceValue || row.label || row.driver);
        const suffix = classificationSuffix(row.classification);
        if (!suffix) {
            return row.key;
        }

        const familyKeyMap = {
            'previous ye approved target changes': 'approved',
            productivity: 'prod',
            arc: 'mbc',
            lms: 'lms',
            'op plan': 'opplan',
            'vacation replacement': 'vac',
            content: 'content',
            sourcing: 'sourcing',
            launch: 'launch',
            'mfg opt': 'mfgopt',
            containment: 'containment',
            'other/excess': 'others',
            'additional straight time hours adjustment': 'astadj'
        };
        const prefix = familyKeyMap[family];
        return prefix ? `${prefix}-${suffix}` : row.key;
    }

    getCommentLookupRowKeys(rowKey) {
        const canonical = this.getLegacyCompatibleCommentRowKey(rowKey);
        if (canonical === rowKey) {
            const aliasEntry = Object.entries(COMMENT_ROW_KEY_ALIASES).find(([, aliasValue]) => aliasValue === rowKey);
            return aliasEntry ? [rowKey, aliasEntry[0]] : [rowKey];
        }
        return [canonical, rowKey];
    }

    getCommentLookupTableNames(tableName, rowKey) {
        const names = new Set([tableName]);
        if (ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(rowKey)) {
            names.add('driver');
            names.add('hours');
        }
        return [...names];
    }

    getCommentsForCell(tableName, rowKey, monthKey) {
        const rows = this.getCommentLookupRowKeys(rowKey);
        const tableNames = this.getCommentLookupTableNames(tableName, rowKey);
        const comments = [];
        tableNames.forEach((lookupTable) => {
            rows.forEach((lookupRow) => {
                const cellKey = this.getGridCellKey(lookupTable, lookupRow, monthKey);
                comments.push(...(this.commentRowsByCellKey[cellKey] || []));
            });
        });
        return comments;
    }

    getCellCommentCount(tableName, rowKey, monthKey) {
        return this.getCommentsForCell(tableName, rowKey, monthKey).length;
    }

    getCommentIconClass(tableName, rowKey, monthKey) {
        const cellKey = this.getGridCellKey(tableName, rowKey, monthKey);
        if (ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(rowKey) && this.getExistingAdditionalStReason(monthKey)) {
            return 'cell-comment-icon cell-comment-icon_existing';
        }
        if (this.isPendingCommentCell(tableName, rowKey, monthKey)) {
            return 'cell-comment-icon cell-comment-icon_pending';
        }
        if (this.sessionSavedCommentCellKeys.has(cellKey)) {
            return 'cell-comment-icon cell-comment-icon_session';
        }
        return this.getCellCommentCount(tableName, rowKey, monthKey) > 0
            ? 'cell-comment-icon cell-comment-icon_existing'
            : 'cell-comment-icon';
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

    getExistingAdditionalStReason(monthKey) {
        const reasonCellKey = this.getGridCellKey('hoursJustification', ADDITIONAL_ST_REASON_ROW_KEY, monthKey);
        const sharedMonthlyComment = (this.commentRowsByCellKey[reasonCellKey] || [])[0] || null;
        if (sharedMonthlyComment) {
            return sharedMonthlyComment;
        }
        for (const legacyRowKey of ['astjust-ots', 'astjust-skilled', 'astjust-salaried']) {
            const legacyMonthlyKey = this.getGridCellKey('hoursJustification', legacyRowKey, monthKey);
            const legacyYearKey = this.getGridCellKey('hoursJustification', legacyRowKey, 'year');
            const legacyComment =
                (this.commentRowsByCellKey[legacyMonthlyKey] || [])[0] ||
                (this.commentRowsByCellKey[legacyYearKey] || [])[0] ||
                null;
            if (legacyComment) {
                return legacyComment;
            }
        }
        return null;
    }

    showToast(title, message, variant = 'info') {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    isPendingCommentCell(tableName, rowKey, monthKey) {
        if (!this.commentModalOpen || !this.selectedCommentCell) {
            return false;
        }
        return this.selectedCommentCell.tableName === tableName &&
            this.selectedCommentCell.rowKey === rowKey &&
            this.selectedCommentCell.monthKey === monthKey &&
            !!this.commentDraft?.trim();
    }

    getMissingAdditionalStReasons() {
        const baselineMap = new Map();
        this.baselineSections.forEach((section) => {
            (section.rows || []).forEach((row) => baselineMap.set(row.key, row));
        });
        const missing = [];
        this.renderedSections.forEach((section) => {
            (section.rows || []).forEach((row) => {
                if (!ADDITIONAL_ST_ADJUSTMENT_ROW_KEYS.includes(row.key)) {
                    return;
                }
                const baselineRow = baselineMap.get(row.key);
                EDITABLE_MONTH_KEYS.forEach((monthKey) => {
                    const currentValue = Number(row.values?.[monthKey]) || 0;
                    const previousValue = Number(baselineRow?.values?.[monthKey]) || 0;
                    if (currentValue !== previousValue && !this.getExistingAdditionalStReason(monthKey)) {
                        missing.push(monthKey.toUpperCase());
                    }
                });
            });
        });
        return missing;
    }

    handleCellContextMenu(event) {
        event.preventDefault();
        const tableName = event.currentTarget.dataset.tableName || event.currentTarget.dataset.table;
        const rowKey = event.currentTarget.dataset.rowKey;
        const monthKey = event.currentTarget.dataset.monthKey;
        const monthLabel = this.monthColumns.find((column) => column.key === monthKey)?.label || monthKey;
        this.selectedCommentCell = {
            tableName,
            rowKey,
            rowLabel: event.currentTarget.dataset.rowLabel,
            monthKey,
            monthLabel,
            classification: event.currentTarget.dataset.classification,
            sectionName: event.currentTarget.dataset.sectionName,
            cellKey: this.getGridCellKey(
                tableName,
                rowKey,
                monthKey
            ),
            supportsJustification: event.currentTarget.dataset.supportsJustification === 'true',
            isJustification: false
        };
        this.commentMenuStyle = `top:${event.clientY + 8}px;left:${event.clientX + 8}px;`;
        this.commentMenuOpen = true;
    }

    handleCellCommentClick(event) {
        event.preventDefault();
        const tableName = event.currentTarget.dataset.tableName || event.currentTarget.dataset.table;
        const rowKey = event.currentTarget.dataset.rowKey;
        const monthKey = event.currentTarget.dataset.monthKey;
        const monthLabel = this.monthColumns.find((column) => column.key === monthKey)?.label || monthKey;
        this.selectedCommentCell = {
            tableName,
            rowKey,
            rowLabel: event.currentTarget.dataset.rowLabel,
            monthKey,
            monthLabel,
            classification: event.currentTarget.dataset.classification,
            sectionName: event.currentTarget.dataset.sectionName,
            cellKey: this.getGridCellKey(tableName, rowKey, monthKey),
            supportsJustification: event.currentTarget.dataset.supportsJustification === 'true',
            isJustification: false
        };
        const rect = event.currentTarget.getBoundingClientRect();
        this.commentMenuStyle = `top:${rect.bottom + 6}px;left:${rect.left}px;`;
        this.commentMenuOpen = true;
    }

    handleDismissCommentMenu() {
        this.commentMenuOpen = false;
    }

    handleViewTabChange(event) {
        const nextTab = event.currentTarget.dataset.tab;
        if (nextTab === 'adjustments' && !this.showAdjustmentsTab) {
            return;
        }
        this.activeViewTab = nextTab;
    }

    normalizeActiveViewTab() {
        const allowedTabs = [
            'input',
            'summary',
            this.showAdjustmentsTab ? 'adjustments' : null
        ].filter(Boolean);

        if (!allowedTabs.includes(this.activeViewTab)) {
            this.activeViewTab = 'input';
        }
    }

    handleClassificationFilterChange(event) {
        this.selectedClassificationFilter = event.detail?.value || 'All';
    }

    handleDriverFilterChange(event) {
        this.selectedDriverFilter = event.detail?.value || 'All';
    }

    handleResetFilters() {
        this.selectedClassificationFilter = 'All';
        this.selectedDriverFilter = 'All';
    }

    handleExpandAll() {
        this.openSections = {
            nonDriver: true,
            driver: true,
            hours: true
        };
    }

    handleCollapseAll() {
        this.openSections = {
            nonDriver: false,
            driver: false,
            hours: false
        };
    }

    handleSectionToggle(event) {
        const sectionName = event.currentTarget.dataset.name;
        this.openSections = {
            ...this.openSections,
            [sectionName]: !this.openSections[sectionName]
        };
    }

    handleCellFocus(event) {
        const tableName = event.currentTarget.dataset.tableName;
        const rowKey = event.currentTarget.dataset.rowKey;
        const monthKey = event.currentTarget.dataset.monthKey;
        this.selectCommentCell(tableName, rowKey, monthKey);
    }

    handleGridInputWheel(event) {
        event.currentTarget.blur();
    }

    handleOpenCommentModal() {
        this.commentMenuOpen = false;
        this.editingCommentId = null;
        this.commentDraft = '';
        this.commentModalOpen = true;
    }

    handleOpenJustificationFromMenu() {
        if (!this.selectedCommentCell?.supportsJustification) {
            this.commentMenuOpen = false;
            return;
        }
        const existingReason = this.getExistingAdditionalStReason(this.selectedCommentCell.monthKey);
        this.selectedCommentCell = {
            tableName: 'hoursJustification',
            rowKey: ADDITIONAL_ST_REASON_ROW_KEY,
            rowLabel: 'Additional ST Adjustment Reason',
            monthKey: this.selectedCommentCell.monthKey,
            monthLabel: this.selectedCommentCell.monthLabel,
            classification: 'Shared',
            sectionName: this.selectedCommentCell.sectionName,
            cellKey: this.getGridCellKey('hoursJustification', ADDITIONAL_ST_REASON_ROW_KEY, this.selectedCommentCell.monthKey),
            supportsJustification: true,
            isJustification: true
        };
        this.commentMenuOpen = false;
        this.editingCommentId = existingReason?.id || null;
        this.commentDraft = existingReason?.commentText || '';
        this.commentModalOpen = true;
    }

    handleCloseCommentModal() {
        this.commentModalOpen = false;
        this.commentDraft = '';
        this.editingCommentId = null;
    }

    handleCommentDraftChange(event) {
        this.commentDraft = event.detail?.value || '';
    }

    handleEditComment(event) {
        this.editingCommentId = event.currentTarget.dataset.commentId;
        this.commentDraft = event.currentTarget.dataset.commentText || '';
    }

    async handleSaveComment() {
        if (this.disableCommentSave) {
            return;
        }
        this.isSavingComment = true;
        this.errorMessage = null;
        try {
            const savedComment = await saveBudgetComment({
                gwbYearId: this.recordId,
                commentId: this.editingCommentId || null,
                tableName: this.selectedCommentCell.tableName,
                rowKey: this.selectedCommentCell.rowKey,
                rowLabel: this.selectedCommentCell.rowLabel,
                monthKey: this.selectedCommentCell.monthKey,
                classification: this.selectedCommentCell.classification,
                commentText: this.commentDraft.trim(),
                valueSnapshot: String(this.findRenderedRow(this.selectedCommentCell.sectionName, this.selectedCommentCell.rowKey)?.values?.[this.selectedCommentCell.monthKey] ?? '')
            });
            this.addCommentToState(savedComment);
            if (savedComment?.cellKey) {
                this.sessionSavedCommentCellKeys.add(savedComment.cellKey);
            }
            this.commentDraft = '';
            this.editingCommentId = null;
            this.applyDerivedRows();
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to save the budget comment.';
        } finally {
            this.isSavingComment = false;
        }
    }

    buildSummaryRow(rowMap, rowKey, label, mode) {
        const row = rowMap.get(rowKey);
        if (!row) {
            return null;
        }
        const values = row.values || {};
        let yearEndValue;
        let currentYearAverage;
        if (mode === 'sum') {
            yearEndValue = sumMonths(values);
            currentYearAverage = computeAverageMonths(values);
        } else if (mode === 'avg') {
            yearEndValue = values?.dec ?? null;
            currentYearAverage = computeAverageMonths(values);
        } else {
            yearEndValue = values?.dec ?? null;
            currentYearAverage = values?.dec ?? null;
        }
        return {
            key: rowKey,
            label,
            previousYear: formatValue(values?.prevDec, row.valueType),
            yearEnd: formatValue(yearEndValue, row.valueType),
            currentYearAverage: formatValue(currentYearAverage, row.valueType)
        };
    }

    buildComparisonRow(rowMap, rowKey, label) {
        const row = rowMap.get(rowKey);
        if (!row) {
            return null;
        }
        const previousYear = row.values?.prevDec;
        const currentYear = row.values?.dec;
        const hasData = !isEmptyMonthValue(previousYear) || !isEmptyMonthValue(currentYear);
        if (!hasData) {
            return null;
        }
        const delta = (Number(currentYear) || 0) - (Number(previousYear) || 0);
        return {
            key: rowKey,
            label,
            previousYear: formatValue(previousYear, row.valueType),
            currentYear: formatValue(currentYear, row.valueType),
            delta: formatValue(delta, row.valueType)
        };
    }

    applyStructuralDerivedRows(rowMap) {
        this.applyCalculatedVolume(rowMap);
        this.applyVolumeVariance(rowMap);
        this.applyGpsTotalSotDays(rowMap);
        this.applyStampingSotEquivalentDaysTotal(rowMap);
        this.applyTotalManpower(rowMap);
        this.applyVacationCoverage(rowMap);
        this.applyTotalManpower(rowMap);
        this.applyClassificationTotalRows(rowMap);
    }

    applyClassificationTotalRows(rowMap) {
        rowMap.forEach((row) => {
            if (row.classification !== 'Total' || row.lineType !== 'Total') {
                return;
            }
            if (row.sourceType === 'Derived') {
                return;
            }
            if (row.formulaKey && HOURS_FORMULA_KEYS.has(row.formulaKey)) {
                return;
            }

            const siblingRows = [];
            const currentFamilyIdentity = normalizeFamilyIdentity(row.sourceValue || row.label || row.driver);
            rowMap.forEach((candidate) => {
                if (candidate.key === row.key) {
                    return;
                }
                if (candidate.sourceType !== row.sourceType) {
                    return;
                }
                if (normalizeFamilyIdentity(candidate.sourceValue || candidate.label || candidate.driver) !== currentFamilyIdentity) {
                    return;
                }
                if (!['OTS', 'Skilled', 'Salaried'].includes(candidate.classification)) {
                    return;
                }
                siblingRows.push(candidate);
            });

            if (!siblingRows.length) {
                return;
            }

            if (row.valueType === 'percent') {
                row.values = this.buildWeightedClassificationTotalValues(rowMap, siblingRows);
                return;
            }

            row.values = this.buildSummedClassificationTotalValues(siblingRows);
        });
    }

    buildSummedClassificationTotalValues(rows) {
        return MONTH_KEYS.reduce((values, monthKey) => {
            const monthValues = (rows || []).map((row) => row?.values?.[monthKey]);
            values[monthKey] = monthValues.some((value) => !isEmptyMonthValue(value))
                ? roundValue(monthValues.reduce((sum, value) => sum + (Number(value) || 0), 0), 1)
                : null;
            return values;
        }, {});
    }

    buildWeightedClassificationTotalValues(rowMap, rows) {
        return MONTH_KEYS.reduce((values, monthKey) => {
            const weightedValues = (rows || []).map((row) => ({
                value: row?.values?.[monthKey],
                weight: this.getClassificationWeight(rowMap, row?.classification, monthKey)
            })).filter((entry) => !isEmptyMonthValue(entry.value));
            values[monthKey] = this.weightedAverage(weightedValues);
            return values;
        }, {});
    }

    getClassificationWeight(rowMap, classification, monthKey) {
        const suffix = classificationSuffix(classification);
        if (!suffix) {
            return 0;
        }
        return Number(rowMap.get(`total-${suffix}`)?.values?.[monthKey]) || 0;
    }

    applyHourDerivedRows(rowMap) {
        const classificationMetrics = {};
        ['OTS', 'Skilled', 'Salaried'].forEach((classification) => {
            const suffix = classificationSuffix(classification);
            classificationMetrics[suffix] = {};
            MONTH_KEYS.forEach((monthKey) => {
                classificationMetrics[suffix][monthKey] = this.calculateHoursForMonth(rowMap, classification, monthKey);
            });
        });

        rowMap.forEach((row) => {
            if (!HOURS_FORMULA_KEYS.has(row.formulaKey)) {
                return;
            }

            if (row.formulaKey === 'ahpuMonthly') {
                row.values = this.buildAhpuMonthlyValues(rowMap);
                return;
            }

            if (row.formulaKey === 'ahpuYtd') {
                row.values = this.buildAhpuYtdValues(rowMap);
                return;
            }

            if (row.formulaKey === 'whpuMonthly') {
                row.values = this.buildWhpuMonthlyValues(rowMap);
                return;
            }

            if (row.classification === 'Total') {
                row.values = this.buildTotalHoursValues(rowMap, classificationMetrics, row.formulaKey);
                return;
            }

            const suffix = classificationSuffix(row.classification);
            if (!classificationMetrics[suffix]) {
                return;
            }

            row.values = MONTH_KEYS.reduce((values, monthKey) => {
                values[monthKey] = classificationMetrics[suffix][monthKey][row.formulaKey];
                return values;
            }, {});
        });
    }

    buildAhpuMonthlyValues(rowMap) {
        const totalHoursValues = this.buildCalculatedHoursSummaryValues(rowMap, 'totalHours');
        const isStamping = normalizeSectorKey(this.header?.sector) === 'stamping';
        const denominatorRow = rowMap.get(isStamping ? 'stampingScheduledVolumePieces' : 'scheduledVolume');
        return MONTH_KEYS.reduce((values, monthKey) => {
            values[monthKey] = buildAhpuMonthlyValue(
                totalHoursValues?.[monthKey],
                denominatorRow?.values?.[monthKey],
                isStamping
            );
            return values;
        }, {});
    }

    buildAhpuYtdValues(rowMap) {
        const totalHoursValues = this.buildCalculatedHoursSummaryValues(rowMap, 'totalHours');
        const isStamping = normalizeSectorKey(this.header?.sector) === 'stamping';
        const denominatorValues = rowMap.get(isStamping ? 'stampingScheduledVolumePieces' : 'scheduledVolume')?.values || {};
        return MONTH_KEYS.reduce((values, monthKey) => {
            if (monthKey === 'prevDec') {
                values[monthKey] = buildAhpuMonthlyValue(totalHoursValues?.[monthKey], denominatorValues?.[monthKey], isStamping);
                return values;
            }
            values[monthKey] = buildAhpuMonthlyValue(
                sumMonthsThrough(totalHoursValues, monthKey),
                sumMonthsThrough(denominatorValues, monthKey),
                isStamping
            );
            return values;
        }, {});
    }

    buildWhpuMonthlyValues(rowMap) {
        return MONTH_KEYS.reduce((values, monthKey) => {
            const totalOts = Number(rowMap.get('total-ots')?.values?.[monthKey]) || 0;
            const totalSkilled = Number(rowMap.get('total-skilled')?.values?.[monthKey]) || 0;
            const totalSalaried = Number(rowMap.get('total-salaried')?.values?.[monthKey]) || 0;
            const totalManpower = totalOts + totalSkilled + totalSalaried;
            const productiveManpower = totalManpower - (
                (totalOts * percentToDecimal(rowMap.get('absenteeism-ots')?.values?.[monthKey])) +
                (totalSkilled * percentToDecimal(rowMap.get('absenteeism-skilled')?.values?.[monthKey])) +
                (totalSalaried * percentToDecimal(rowMap.get('absenteeism-salaried')?.values?.[monthKey]))
            );
            const netJph = Number(rowMap.get('netJph')?.values?.[monthKey]) || 0;
            const crews = Number(rowMap.get('crews')?.values?.[monthKey]) || 0;
            values[monthKey] = netJph && crews
                ? roundValue(productiveManpower / (netJph * crews), 1)
                : 0;
            return values;
        }, {});
    }

    applyCalculatedVolume(rowMap) {
        const targetRow = rowMap.get('calcVolume');
        if (!targetRow) {
            return;
        }

        const sourceRows = [
            rowMap.get('netJph'),
            rowMap.get('paidHoursPerCrew'),
            rowMap.get('productionDays'),
            rowMap.get('eqSotDays'),
            rowMap.get('shifts')
        ];
        const nextValues = {};

        MONTH_KEYS.forEach((monthKey) => {
            const rawValues = sourceRows.map((row) => row?.values?.[monthKey]);
            const hasData = rawValues.some((value) => !isEmptyMonthValue(value));
            if (!hasData) {
                nextValues[monthKey] = null;
                return;
            }

            nextValues[monthKey] = roundValue(
                (Number(rowMap.get('netJph')?.values?.[monthKey]) || 0) *
                (Number(rowMap.get('paidHoursPerCrew')?.values?.[monthKey]) || 0) *
                (
                    (Number(rowMap.get('productionDays')?.values?.[monthKey]) || 0) +
                    (Number(rowMap.get('eqSotDays')?.values?.[monthKey]) || 0)
                ) *
                (Number(rowMap.get('shifts')?.values?.[monthKey]) || 0),
                0
            );
        });

        targetRow.values = nextValues;
    }

    applyVolumeVariance(rowMap) {
        const targetRow = rowMap.get('volumeVariance');
        if (!targetRow) {
            return;
        }

        const nextValues = {};
        MONTH_KEYS.forEach((monthKey) => {
            const scheduledValue = rowMap.get('scheduledVolume')?.values?.[monthKey];
            const calculatedValue = rowMap.get('calcVolume')?.values?.[monthKey];
            const hasData = !isEmptyMonthValue(scheduledValue) || !isEmptyMonthValue(calculatedValue);
            nextValues[monthKey] = hasData
                ? (Number(scheduledValue) || 0) - (Number(calculatedValue) || 0)
                : null;
        });

        targetRow.values = nextValues;
    }

    applyGpsTotalSotDays(rowMap) {
        const targetRow = rowMap.get('gpsTotalSotDays');
        if (!targetRow) {
            return;
        }

        targetRow.values = buildGpsTotalSotDaysValues(
            rowMap.get('gpsSotDaysWeekends')?.values,
            rowMap.get('eqSotDays')?.values
        );
    }

    applyStampingSotEquivalentDaysTotal(rowMap) {
        const targetRow = rowMap.get('stampingSotEquivalentDaysTotal');
        if (!targetRow) {
            return;
        }

        targetRow.values = buildStampingSotEquivalentDaysTotalValues(
            rowMap.get('productionDays')?.values,
            rowMap.get('stampingEquivalentSotPct')?.values
        );
    }

    applyTotalManpower(rowMap) {
        ['OTS', 'Skilled', 'Salaried'].forEach((classification) => {
            const suffix = classificationSuffix(classification);
            const totalRow = rowMap.get(`total-${suffix}`);
            if (!totalRow) {
                return;
            }

            const adjustmentRowsByKey = this.getHeadcountDriverAdjustmentRows(rowMap, suffix);

            totalRow.values = buildTotalManpowerValues(
                rowMap.get(`base-${suffix}`)?.values || {},
                rowMap.get(`advanced-${suffix}`)?.values || {},
                adjustmentRowsByKey
            );
        });
    }

    applyVacationCoverage(rowMap) {
        const vacationRow = rowMap.get('vac-ots');
        if (!vacationRow || !this.vacationCoverageConfig) {
            return;
        }
        if (!this.canEdit) {
            return;
        }

        const adjustmentRowsByKey = {};
        rowMap.forEach((row) => {
            if (row.sourceType !== 'Driver') {
                return;
            }
            if (row.classification !== 'OTS') {
                return;
            }
            if (row.key === vacationRow.key || row.sourceValue === 'Vacation Replacement') {
                return;
            }
            adjustmentRowsByKey[row.key] = row.values || {};
        });

        vacationRow.values = buildAssemblyVacationCoverageValues({
            sector: this.header?.sector,
            classification: 'OTS',
            vacationPercent: this.vacationCoverageConfig?.vacationPercent,
            entryMonthKey: this.vacationCoverageConfig?.entryMonthKey,
            exitMonthKey: this.vacationCoverageConfig?.exitMonthKey,
            currentValues: vacationRow.values || {},
            baseValues: rowMap.get('base-ots')?.values || {},
            approvedValues: rowMap.get('advanced-ots')?.values || {},
            adjustmentRowsByKey
        });
    }

    calculateHoursForMonth(rowMap, classification, monthKey) {
        const suffix = classificationSuffix(classification);
        const totalManpowerRaw = rowMap.get(`total-${suffix}`)?.values?.[monthKey];
        const absenteeismRaw = rowMap.get(`absenteeism-${suffix}`)?.values?.[monthKey];
        const nsotRaw = rowMap.get(`nsot-${suffix}`)?.values?.[monthKey];
        const paidHoursRaw = rowMap.get('paidHoursPerCrew')?.values?.[monthKey];
        const availableDaysRaw = rowMap.get('availableDays')?.values?.[monthKey];
        const productionDaysRaw = rowMap.get('productionDays')?.values?.[monthKey];
        const eqSotDaysRaw = rowMap.get('eqSotDays')?.values?.[monthKey];
        const crewsRaw = rowMap.get('crews')?.values?.[monthKey];
        const shiftsRaw = rowMap.get('shifts')?.values?.[monthKey];
        const vacationRow = rowMap.get(`vac-${suffix}`);
        const additionalStraightAdjustmentRaw = rowMap.get(`astadj-${suffix}`)?.values?.[monthKey];

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

        return calculateHourMetrics({
            totalManpower: Number(totalManpowerRaw) || 0,
            absenteeismPct: percentToDecimal(absenteeismRaw),
            nsotPct: percentToDecimal(nsotRaw),
            paidHoursPerCrew: Number(paidHoursRaw) || 0,
            availableDays: Number(availableDaysRaw) || 0,
            productionDays: Number(productionDaysRaw) || 0,
            eqSotDays: Number(eqSotDaysRaw) || 0,
            crews: Number(crewsRaw) || 1,
            shifts: Number(shiftsRaw) || 0,
            vacationValues: vacationRow?.values || {},
            monthKey,
            classification,
            additionalStraightAdjustment: Number(additionalStraightAdjustmentRaw) || 0
        });
    }

    buildTotalHoursValues(rowMap, classificationMetrics, formulaKey) {
        return MONTH_KEYS.reduce((values, monthKey) => {
            const suffixes = ['ots', 'skilled', 'salaried'];
            const classifications = suffixes.map((suffix) => classificationMetrics[suffix][monthKey]);
            if (formulaKey === 'combinedAbsence') {
                const weightedValues = classifications
                    .map((metrics, index) => ({
                        value: metrics[formulaKey],
                        weight: Number(rowMap.get(`total-${suffixes[index]}`)?.values?.[monthKey]) || 0
                    }))
                    .filter((entry) => !isEmptyMonthValue(entry.value));
                values[monthKey] = this.weightedAverage(weightedValues);
                return values;
            }

            const monthValues = classifications.map((metrics) => metrics[formulaKey]);
            values[monthKey] = monthValues.some((value) => !isEmptyMonthValue(value))
                ? roundValue(monthValues.reduce((sum, value) => sum + (Number(value) || 0), 0), 1)
                : null;
            return values;
        }, {});
    }

    weightedAverage(entries) {
        if (!entries.length) {
            return null;
        }

        const totals = entries.reduce((accumulator, entry) => {
            const weight = Number(entry.weight) || 0;
            const value = Number(entry.value) || 0;
            accumulator.weighted += value * weight;
            accumulator.weight += weight;
            return accumulator;
        }, { weighted: 0, weight: 0 });

        if (!totals.weight) {
            return 0;
        }

        return roundValue(totals.weighted / totals.weight, 1);
    }
}