import { api, LightningElement } from "lwc";
import getSummaryData from "@salesforce/apex/ProdPlanSummaryCntrl.getSummaryData";

const MONTH_FIELDS = [
    { key: "jan", field: "currentYearJanAdjustment", label: "JAN" },
    { key: "feb", field: "currentYearFebAdjustment", label: "FEB" },
    { key: "mar", field: "currentYearMarAdjustment", label: "MAR" },
    { key: "apr", field: "currentYearAprAdjustment", label: "APR" },
    { key: "may", field: "currentYearMayAdjustment", label: "MAY" },
    { key: "jun", field: "currentYearJunAdjustment", label: "JUN" },
    { key: "jul", field: "currentYearJulAdjustment", label: "JUL" },
    { key: "aug", field: "currentYearAugAdjustment", label: "AUG" },
    { key: "sep", field: "currentYearSepAdjustment", label: "SEP" },
    { key: "oct", field: "currentYearOctAdjustment", label: "OCT" },
    { key: "nov", field: "currentYearNovAdjustment", label: "NOV" },
    { key: "dec", field: "currentYearDecAdjustment", label: "DEC" }
];

const TARGET_HEADER_ROW_INDEX = 0;
const ACTUAL_FORECAST_HEADER_ROW_INDEX = 4;
const ABOVE_BELOW_ROW_INDEX = 8;
const TOTAL_DATA_COLUMNS = 13; // prevDec + 12 months

/**
 * Apex `primaryHeaderPlacementColumn` / `secondaryHeaderPlacementColumn` are
 * 1-indexed where column 1 = the row-label column. The data array (prevDec
 * + 12 months) starts at placement index 2, so subtract 2 to translate.
 */
const PLACEMENT_COLUMN_OFFSET = 2;

export default class ProductivityPlanningSummary extends LightningElement {
    _appliedFilterWrapper = {};
    summaryRows = [];
    isLoading = false;
    errorMessage = "";
    hasFetched = false;

    @api
    get appliedFilterWrapper() {
        return this._appliedFilterWrapper;
    }
    set appliedFilterWrapper(value) {
        this._appliedFilterWrapper = value || {};
        this.fetchSummary();
    }

    async fetchSummary() {
        if (!this.hasMeaningfulFilters) {
            this.summaryRows = [];
            this.hasFetched = false;
            return;
        }

        this.isLoading = true;
        this.errorMessage = "";

        try {
            const rows = await getSummaryData({ filters: this._appliedFilterWrapper });
            this.summaryRows = Array.isArray(rows) ? rows : [];
            this.hasFetched = true;
        } catch (error) {
            this.summaryRows = [];
            this.errorMessage = this.extractErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        this.fetchSummary();
    }

    extractErrorMessage(error) {
        if (!error) {
            return "Unable to load summary data.";
        }
        if (typeof error === "string") {
            return error;
        }
        return error?.body?.message || error?.message || "Unable to load summary data.";
    }

    get hasMeaningfulFilters() {
        const wrapper = this._appliedFilterWrapper || {};
        return Object.values(wrapper).some((value) => value !== null && value !== undefined && value !== "");
    }

    get planYear() {
        return this.summaryRows[0]?.year || new Date().getFullYear();
    }

    get previousYear() {
        return this.summaryRows[0]?.previousYear || this.planYear - 1;
    }

    get yearSuffix() {
        return String(this.planYear).slice(-2);
    }

    get prevYearSuffix() {
        return String(this.previousYear).slice(-2);
    }

    get columnHeaders() {
        const headers = [{ key: "prevDec", label: `DEC ${this.prevYearSuffix}` }];
        MONTH_FIELDS.forEach((m) => {
            headers.push({ key: m.key, label: `${m.label} ${this.yearSuffix}` });
        });
        return headers;
    }

    get displayRows() {
        if (!this.summaryRows.length) {
            return [];
        }

        return this.summaryRows.map((row) => {
            if (row.isHeaderRow && row.rowIndex === TARGET_HEADER_ROW_INDEX) {
                return this.buildTargetBannerRow(row);
            }
            if (row.isHeaderRow && row.rowIndex === ACTUAL_FORECAST_HEADER_ROW_INDEX) {
                return this.buildActualForecastBannerRow(row);
            }
            if (row.rowIndex === ABOVE_BELOW_ROW_INDEX) {
                return this.buildAboveBelowRow(row);
            }
            return this.buildDataRow(row);
        });
    }

    buildTargetBannerRow(row) {
        return {
            key: `row-${row.rowIndex}`,
            isTargetBanner: true,
            isActualForecastBanner: false,
            isDataRow: false,
            isIndicatorRow: false,
            rowClass: "pps-banner-row pps-banner-row_target",
            rowLabelClass: "pps-row-label pps-row-label_banner pps-row-label_target",
            rowLabel: row.rowPrimaryHeader,
            spanCellClass: "pps-banner-cell pps-banner-cell_target",
            spanCellColspan: TOTAL_DATA_COLUMNS
        };
    }

    buildActualForecastBannerRow(row) {
        const primaryIndex = (row.primaryHeaderPlacementColumn ?? 0) - PLACEMENT_COLUMN_OFFSET;
        const secondaryIndex = (row.secondaryHeaderPlacementColumn ?? 0) - PLACEMENT_COLUMN_OFFSET;
        const isAllActuals = secondaryIndex >= TOTAL_DATA_COLUMNS;
        const isAllForecast = secondaryIndex <= 0;

        if (isAllActuals || isAllForecast) {
            const isActuals = isAllActuals;
            const rowLabelRaw = isActuals ? row.rowPrimaryHeader : row.rowSecondaryHeader;
            const cleanedLabel = this.stripDirectionArrows(rowLabelRaw) || (isActuals ? "Actuals" : "Forecast");
            const tone = isActuals ? "actual" : "forecast";
            return {
                key: `row-${row.rowIndex}`,
                isTargetBanner: false,
                isSinglePhaseBanner: true,
                isActualForecastBanner: false,
                isDataRow: false,
                isIndicatorRow: false,
                rowClass: `pps-banner-row pps-banner-row_single-phase pps-banner-row_single-phase_${tone}`,
                rowLabelClass: `pps-row-label pps-row-label_banner pps-row-label_single-phase pps-row-label_single-phase_${tone}`,
                rowLabel: cleanedLabel,
                spanCellClass: `pps-banner-cell pps-banner-cell_single-phase pps-banner-cell_${tone}`,
                spanCellColspan: TOTAL_DATA_COLUMNS
            };
        }

        const cells = [];
        for (let i = 0; i < TOTAL_DATA_COLUMNS; i++) {
            const isActualSection = i < secondaryIndex;
            const sectionClass = isActualSection ? "pps-banner-cell_actual" : "pps-banner-cell_forecast";
            let label = "";
            let labelClass = "";
            if (i === primaryIndex) {
                label = row.rowPrimaryHeader;
                labelClass = " pps-banner-cell_label pps-banner-cell_label-actual";
            } else if (i === secondaryIndex) {
                label = row.rowSecondaryHeader;
                labelClass = " pps-banner-cell_label pps-banner-cell_label-forecast";
            }
            cells.push({
                key: `r4-c${i}`,
                label,
                cssClass: `pps-banner-cell ${sectionClass}${labelClass}`
            });
        }
        return {
            key: `row-${row.rowIndex}`,
            isTargetBanner: false,
            isSinglePhaseBanner: false,
            isActualForecastBanner: true,
            isDataRow: false,
            isIndicatorRow: false,
            rowClass: "pps-banner-row pps-banner-row_actual-forecast",
            rowLabelClass: "pps-row-label pps-row-label_banner pps-row-label_actual-forecast",
            rowLabel: "",
            actualForecastCells: cells
        };
    }

    stripDirectionArrows(label) {
        if (!label) {
            return "";
        }
        return String(label).replace(/[←→]/g, "").trim();
    }

    buildDataRow(row) {
        const cells = [
            this.buildValueCell(row, "prevDec", row.previousYearDecAdjustment)
        ];
        MONTH_FIELDS.forEach((m) => {
            cells.push(this.buildValueCell(row, m.key, row[m.field]));
        });
        return {
            key: `row-${row.rowIndex}`,
            isTargetBanner: false,
            isActualForecastBanner: false,
            isDataRow: true,
            isIndicatorRow: false,
            rowClass: "pps-data-row",
            rowLabelClass: "pps-row-label",
            rowLabel: row.rowPrimaryHeader,
            valueCells: cells
        };
    }

    buildAboveBelowRow(row) {
        const cells = [
            this.buildIndicatorCell(row, "prevDec", row.previousYearDecAdjustment)
        ];
        MONTH_FIELDS.forEach((m) => {
            cells.push(this.buildIndicatorCell(row, m.key, row[m.field]));
        });
        return {
            key: `row-${row.rowIndex}`,
            isTargetBanner: false,
            isActualForecastBanner: false,
            isDataRow: false,
            isIndicatorRow: true,
            rowClass: "pps-data-row pps-data-row_indicator",
            rowLabelClass: "pps-row-label pps-row-label_indicator",
            rowLabel: row.rowPrimaryHeader,
            indicatorCells: cells
        };
    }

    buildValueCell(row, key, value) {
        return {
            key: `${row.rowIndex}-${key}`,
            value,
            cssClass: "pps-data-cell"
        };
    }

    buildIndicatorCell(row, key, value) {
        const numeric = typeof value === "number" ? value : Number(value);
        const isPositive = Number.isFinite(numeric) && numeric > 0;
        const isNonPositive = Number.isFinite(numeric) && numeric <= 0;

        let directionClass = "";
        if (isPositive) directionClass = " pps-data-cell_indicator-negative";
        else if (isNonPositive) directionClass = " pps-data-cell_indicator-positive";

        return {
            key: `${row.rowIndex}-${key}`,
            value: Number.isFinite(numeric) ? numeric : value,
            isPositive,
            isNonPositive,
            cssClass: `pps-data-cell pps-data-cell_indicator${directionClass}`
        };
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && this.hasFetched && this.summaryRows.length === 0;
    }

    get showTable() {
        return !this.isLoading && !this.errorMessage && this.summaryRows.length > 0;
    }

    get showInitialState() {
        return !this.isLoading && !this.errorMessage && !this.hasFetched && this.summaryRows.length === 0;
    }
}