import { LightningElement, api, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import getForecastData from "@salesforce/apex/InitiativeDetailController.getForecastData";
import getActualData from "@salesforce/apex/InitiativeDetailController.getActualData";
import getAvailablePlantFunctions from "@salesforce/apex/InitiativeDetailController.getAvailablePlantFunctions";
import getAvailableOperations from "@salesforce/apex/InitiativeDetailController.getAvailableOperations";
import saveForecastData from "@salesforce/apex/InitiativeDetailController.saveForecastData";
import saveActualData from "@salesforce/apex/InitiativeDetailController.saveActualData";
import EFFECTIVE_DATE_APPROVAL_STATUS_FIELD from "@salesforce/schema/Initiative__c.Effective_Date_Approval_Status__c";
import hasGwbSystemAdminPermission from '@salesforce/customPermission/GWB_System_Admin';
import hasPlantAdminPermission from '@salesforce/customPermission/Plant_Admin';

const MISMATCH =
  "Value mismatch. Update the Total Position Adjustment value to match the initiative record.";
const FUNCTION_SEARCH_DEBOUNCE_MS = 500;
const UNSAVED_CHANGES_LABEL = "GWB Initiative Detail Planning";
const INITIATIVE_APPROVAL_FIELDS = [EFFECTIVE_DATE_APPROVAL_STATUS_FIELD];

const MOCK_APPROVERS = [
  ["ap-1", "Ann Perkins", "Role 1", "Department 1"],
  ["ap-2", "Ben Wyatt", "Role 2", "Department 1"],
  ["ap-3", "Donna Meagle", "Role 3", "Department 1"],
  ["ap-4", "Jean-Ralphio Saperstein", "Role 4", "Department 2"],
  ["ap-5", "Leslie Knope", "Role 5", "Department 2"],
  ["ap-6", "Ron Swanson", "Role 6", "Department 2"]
].map(([id, name, role, department], index) => ({
  id,
  rowNumber: index + 1,
  name,
  role,
  department
}));

const MOCK_FUNCTIONS = [
  {
    uid: "pf-1",
    plantFunctionId: "pf-1",
    plantFunctionName: "Function Master Name 1",
    programName: "Program Name",
    programCode: "Program Code",
    functionLevel: "Function Level",
    functionArea: "Function Area",
    line: "Line",
    module: "Module",
    crewEditableCount: 3,
    crew1: 1,
    crew2: 1,
    crew3: 1,
    operations: [
      {
        uid: "op-1",
        operationId: "op-1",
        operationIdentifier: "1AEST",
        area: "(E-FORK) Right Side Doors",
        equipment: "FORK",
        comment: "GROUP 1",
        crew1: 2,
        crew2: -1,
        crew3: 2
      },
      {
        uid: "op-2",
        operationId: "op-2",
        operationIdentifier: "1BEST",
        area: "(U-FORK) AM Unload & Stage",
        equipment: "FORK",
        comment: "GROUP 1",
        crew1: -1,
        crew2: 2,
        crew3: 0
      }
    ]
  },
  {
    uid: "pf-2",
    plantFunctionId: "pf-2",
    plantFunctionName: "Function Master Name 2",
    programName: "Program Name",
    programCode: "Program Code",
    functionLevel: "Function Level",
    functionArea: "Function Area",
    line: "Line",
    module: "Module",
    crewEditableCount: 2,
    crew1: 1,
    crew2: 1,
    crew3: 0,
    operations: []
  }
];

const MOCK_AVAILABLE_FUNCTIONS = Array.from({ length: 12 }, (_, index) => ({
  uid: `pf-add-${index + 1}`,
  plantFunctionId: `pf-add-${index + 1}`,
  plantFunctionName: `Function Master Name ${index + 3}`,
  programName: "Program Name",
  programCode: "Program Code",
  functionLevel: "Function Level",
  functionArea: "Function Area",
  line: "Line",
  module: "Module",
  crewEditableCount: (index % 3) + 1,
  crew1: 0,
  crew2: 0,
  crew3: 0,
  operations: []
}));

const MOCK_AVAILABLE_OPERATIONS = [
  ["11DBE", "DOLLY TRAIN FA-R &LB", "TUGGER", "GROUP 2"],
  ["14DBE", "DOLLY TRAIN LH CLOSURES", "TUGGER", "GROUP 2"],
  ["15DBE", "DOLLY TRAIN", "TUGGER", "GROUP 2"],
  ["16DBE", "DOLLY TRAIN AD-D-BN", "FORK", "GROUP 2"],
  ["1AEST", "(E-FORK) Right Side Doors", "FORK", "GROUP 1"],
  ["1BEST", "(U-FORK) AM Unload & Stage", "FORK", "GROUP 1"]
].map(([operationIdentifier, area, equipment, comment], index) => ({
  uid: `op-add-${index + 1}`,
  operationId: `op-add-${index + 1}`,
  operationIdentifier,
  area,
  equipment,
  comment,
  crew1: 0,
  crew2: 0,
  crew3: 0
}));

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function toInt(value) {
  if (value === null || value === undefined || value === "") {
    return 0;
  }
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) {
    throw new Error("Only integer crew values are allowed.");
  }
  return parsed;
}

function rowTotal(row) {
  return toInt(row.crew1) + toInt(row.crew2) + toInt(row.crew3);
}

function totalStatus(totalChangesNeeded, totalChangesMade) {
  return totalChangesNeeded === totalChangesMade ? "match" : "mismatch";
}

function normalizeRows(sections) {
  return (sections || []).map((section) => {
    const rows = (section.gwbFunctions || []).map((row, index) => {
      const functionCrew1 = toInt(row.crew1);
      const functionCrew2 = toInt(row.crew2);
      const functionCrew3 = toInt(row.crew3);
      const operations = (row.operations || []).map((operation) => ({
        ...operation,
        uid: operation.uid || operation.authorizedDatabaseId || operation.operationId,
        crew1: toInt(operation.crew1),
        crew2: toInt(operation.crew2),
        crew3: toInt(operation.crew3),
        total: rowTotal(operation)
      }));
      const hasOperations = operations.length > 0;
      const actualCrew1 = hasOperations
        ? operations.reduce((sum, operation) => sum + operation.crew1, 0)
        : functionCrew1;
      const actualCrew2 = hasOperations
        ? operations.reduce((sum, operation) => sum + operation.crew2, 0)
        : functionCrew2;
      const actualCrew3 = hasOperations
        ? operations.reduce((sum, operation) => sum + operation.crew3, 0)
        : functionCrew3;
      const displayCrew1 =
        hasOperations && row.displayCrew1 !== null && row.displayCrew1 !== undefined
          ? toInt(row.displayCrew1)
          : functionCrew1;
      const displayCrew2 =
        hasOperations && row.displayCrew2 !== null && row.displayCrew2 !== undefined
          ? toInt(row.displayCrew2)
          : functionCrew2;
      const displayCrew3 =
        hasOperations && row.displayCrew3 !== null && row.displayCrew3 !== undefined
          ? toInt(row.displayCrew3)
          : functionCrew3;
      const nextRow = {
        ...row,
        rowNumber: index + 1,
        uid: row.uid || row.workbookId || row.plantFunctionId,
        operations,
        crew1: functionCrew1,
        crew2: functionCrew2,
        crew3: functionCrew3,
        actualCrew1,
        actualCrew2,
        actualCrew3,
        actualTotal: actualCrew1 + actualCrew2 + actualCrew3,
        displayCrew1,
        displayCrew2,
        displayCrew3
      };
      nextRow.total = hasOperations ? nextRow.actualTotal : rowTotal(nextRow);
      return nextRow;
    });
    return {
      ...section,
      rows,
      gwbFunctions: rows,
      totalAdjustments: rows.reduce((sum, row) => sum + row.total, 0)
    };
  });
}

function mockSections() {
  return normalizeRows([
    {
      key: "effective",
      initiativeDateOption: "Effective Date",
      year: 2026,
      month: "Mar",
      editable: true,
      initiativePositionAdjustment: 6,
      addFunctionsAllowed: true,
      hasParentInitiative: false,
      isContainmentDriver: false,
      gwbFunctions: clone(MOCK_FUNCTIONS)
    }
  ]);
}

export default class InitiativeDetailPlanning extends LightningElement {
  @api recordId;
  @api mode = "both";
  @api showTestDataToggle = false;
  @track initiativePositionAdjustment = 6;

  @track testDataMode = false;
  @track activeTab = "forecast";
  @track forecastSections = [];
  @track actualSections = [];
  @track savedForecastSections = [];
  @track savedActualSections = [];
  @track forecastEditMode = false;
  @track actualsEditMode = false;
  @track errorMessage = "";
  @track showFunctionModal = false;
  @track showOperationModal = false;
  @track availableFunctions = [];
  @track availableOperations = [];
  @track changeRequests = [];
  @track showChangeRequestModal = false;
  @track changeRequestStep = 1;
  @track selectedReportingMonth = "";
  @track selectedApproverIds = [];
  @track selectedFunctionIds = [];
  @track selectedOperationIds = [];
  @track functionSearchTerm = "";
  @track operationSearchTerm = "";
  showCreateApprovalModal = false;
  hasGwbSystemAdminPermission = hasGwbSystemAdminPermission;
  hasPlantAdminPermission = hasPlantAdminPermission;
  functionSearchDebounce;
  operationSearchDebounce;
  operationContext;
  _lastUnsavedState = false;

  @wire(getRecord, { recordId: "$recordId", fields: INITIATIVE_APPROVAL_FIELDS })
  initiativeRecord;

  connectedCallback() {
    this.loadData();
  }

  get effectiveTab() {
    if (this.mode === "forecast" || this.mode === "actuals") {
      return this.mode;
    }
    return this.activeTab;
  }

  get showInternalTabs() {
    return this.mode !== "forecast" && this.mode !== "actuals";
  }

  get showTestModeControl() {
    return this.showTestDataToggle;
  }

  get isForecastTab() {
    return this.effectiveTab === "forecast";
  }

  get isActualsTab() {
    return this.effectiveTab === "actuals";
  }

  get isEditMode() {
    return this.isForecastTab ? this.forecastEditMode : this.actualsEditMode;
  }

  @api
  get hasUnsavedChanges() {
    if (!this.forecastEditMode && !this.actualsEditMode) {
      return false;
    }
    return (
      JSON.stringify(this.forecastSections) !==
        JSON.stringify(this.savedForecastSections) ||
      JSON.stringify(this.actualSections) !== JSON.stringify(this.savedActualSections)
    );
  }

  get isActualsLockedByChangeRequest() {
    const latest = this.changeRequests[0];
    return this.isActualsTab && (latest?.status === "Pending" || latest?.status === "Approved");
  }

  get activeTitle() {
    const section = this.activeSections?.[0];
    const label = this.isForecastTab ? "Forecast" : "Actuals";
    return section?.month && section?.year
      ? `${label} for ${section.month}, ${section.year}`
      : label;
  }

  get activeSections() {
    return this.isForecastTab ? this.forecastSections : this.actualSections;
  }

  get canAddFunctions() {
    return this.forecastSections?.[0]?.addFunctionsAllowed !== false;
  }

  get showAddFunctionsButton() {
    return this.isForecastTab && this.canAddFunctions;
  }

  get childInitiativeMessage() {
    return this.canAddFunctions
      ? ""
      : "Plan functions are copied from the parent initiative. Add Functions is hidden for child initiatives.";
  }

  get activeViewSections() {
    return this.activeSections.map((section) => ({
      ...section,
      totalChangesNeeded: this.initiativePositionAdjustment,
      totalChangesMade: section.totalAdjustments,
      totalStatus: totalStatus(this.initiativePositionAdjustment, section.totalAdjustments),
      totalMadeClass:
        totalStatus(this.initiativePositionAdjustment, section.totalAdjustments) === "match"
          ? "changes-made-cell changes-made-cell_match"
          : "changes-made-cell changes-made-cell_mismatch",
      totalStatusIcon:
        totalStatus(this.initiativePositionAdjustment, section.totalAdjustments) === "match"
          ? "utility:check"
          : "utility:error",
      hasRows: (section.gwbFunctions || []).length > 0,
      rows: (section.gwbFunctions || []).map((row) => {
        const crew1Disabled = this.isCrewDisabled(row, section, 1, false);
        const crew2Disabled = this.isCrewDisabled(row, section, 2, false);
        const crew3Disabled = this.isCrewDisabled(row, section, 3, false);
        const rowTotalNeeded =
          this.isActualsTab && (row.operations || []).length > 0
            ? toInt(row.displayCrew1) + toInt(row.displayCrew2) + toInt(row.displayCrew3)
            : row.total;
        return {
          ...row,
          plantFunctionUrl: row.plantFunctionId
            ? `/lightning/r/Plant_Function__c/${row.plantFunctionId}/view`
            : "",
          hasPlantFunctionUrl: Boolean(row.plantFunctionId),
          crew1Disabled,
          crew1Editable: !crew1Disabled,
          crew1DisplayValue: row.displayCrew1 ?? row.crew1,
          crew2Disabled,
          crew2Editable: !crew2Disabled,
          crew2DisplayValue: row.displayCrew2 ?? row.crew2,
          crew3Disabled,
          crew3Editable: !crew3Disabled,
          crew3DisplayValue: row.displayCrew3 ?? row.crew3,
          totalChangesNeeded: rowTotalNeeded,
          totalChangesMade: row.total,
          totalMadeClass: "changes-made-cell",
          operations: (row.operations || []).map((operation) => {
            const operationCrew1Disabled = this.isCrewDisabled(row, section, 1, true);
            const operationCrew2Disabled = this.isCrewDisabled(row, section, 2, true);
            const operationCrew3Disabled = this.isCrewDisabled(row, section, 3, true);
            return {
              ...operation,
              crew1Disabled: operationCrew1Disabled,
              crew1Editable: !operationCrew1Disabled,
              crew2Disabled: operationCrew2Disabled,
              crew2Editable: !operationCrew2Disabled,
              crew3Disabled: operationCrew3Disabled,
              crew3Editable: !operationCrew3Disabled,
              totalChangesNeeded: operation.total
            };
          })
        };
      })
    }));
  }

  get tableColspan() {
    return this.isActualsTab ? 8 : 7;
  }

  get summaryColspan() {
    return this.isActualsTab ? 3 : 2;
  }

  get crewStartColspan() {
    return this.summaryColspan;
  }

  get sectionIconClass() {
    return this.isForecastTab ? "section-icon forecast" : "section-icon actuals";
  }

  get showReportActualsButton() {
    const approvalStatus = getFieldValue(
      this.initiativeRecord?.data,
      EFFECTIVE_DATE_APPROVAL_STATUS_FIELD
    );
    const normalizedApprovalStatus = String(approvalStatus || "")
      .trim()
      .toLowerCase();
    const hasReportActualsOverride =
      this.hasGwbSystemAdminPermission || this.hasPlantAdminPermission;
    const isHiddenStatus =
      normalizedApprovalStatus === "in review" ||
      normalizedApprovalStatus === "approved";
    return this.isActualsTab && hasReportActualsOverride && !isHiddenStatus;
  }

  get reportActualsDisabled() {
    return this.isEditMode || this.isActualsLockedByChangeRequest;
  }

  get editPositionsDisabled() {
    return this.isEditMode || this.isActualsLockedByChangeRequest;
  }

  get disableAddFunctions() {
    return this.selectedFunctionIds.length === 0;
  }

  get disableAddOperations() {
    return this.selectedOperationIds.length === 0;
  }

  get filteredAvailableFunctions() {
    const searchTerm = this.functionSearchTerm.trim().toLowerCase();
    return this.availableFunctions
      .filter((item) => {
        if (!searchTerm) {
          return true;
        }
        return [
          item.plantFunctionName,
          item.programName,
          item.programCode,
          item.functionLevel,
          item.functionArea,
          item.line,
          item.module
        ]
          .filter(Boolean)
          .some((value) => String(value).toLowerCase().includes(searchTerm));
      })
      .map((item) => ({
        ...item,
        checked: this.selectedFunctionIds.includes(item.uid)
      }));
  }

  get filteredAvailableOperations() {
    const searchTerm = this.operationSearchTerm.trim().toLowerCase();
    return this.availableOperations
      .filter((item) => {
        if (!searchTerm) {
          return true;
        }
        return [item.operationIdentifier, item.area, item.equipment, item.comment]
          .filter(Boolean)
          .some((value) => String(value).toLowerCase().includes(searchTerm));
      })
      .map((item) => ({
        ...item,
        checked: this.selectedOperationIds.includes(item.uid)
      }));
  }

  get reportingMonthOptions() {
    return this.actualSections.map((section) => ({
      label: `${section.month}, ${section.year}`,
      value: section.key
    }));
  }

  get selectedReportingSection() {
    return (
      this.actualSections.find((section) => section.key === this.selectedReportingMonth) ||
      this.actualSections[0]
    );
  }

  get changeRequestModalTitle() {
    return this.selectedReportingSection?.month && this.selectedReportingSection?.year
      ? `Reporting Actuals for ${this.selectedReportingSection.month}, ${this.selectedReportingSection.year}`
      : "Reporting Actuals";
  }

  get changeRequestSummaryRows() {
    const rows = [];
    (this.selectedReportingSection?.gwbFunctions || []).forEach((row) => {
      if ((row.operations || []).length) {
        row.operations.forEach((operation) => {
          rows.push({
            id: `${row.uid}-${operation.uid}`,
            functionName: row.plantFunctionName,
            operationName: operation.operationIdentifier,
            total: operation.total
          });
        });
      } else {
        rows.push({
          id: row.uid,
          functionName: row.plantFunctionName,
          operationName: "",
          total: row.total
        });
      }
    });
    return rows.map((row, index) => ({
      ...row,
      rowNumber: index + 1
    }));
  }

  get selectedApprovers() {
    return MOCK_APPROVERS.filter((approver) =>
      this.selectedApproverIds.includes(approver.id)
    );
  }

  get hasSelectedApprovers() {
    return this.selectedApproverIds.length > 0;
  }

  get availableApprovers() {
    return MOCK_APPROVERS.map((approver) => ({
      ...approver,
      checked: this.selectedApproverIds.includes(approver.id)
    }));
  }

  get isChangeRequestStepOne() {
    return this.changeRequestStep === 1;
  }

  get isChangeRequestStepTwo() {
    return this.changeRequestStep === 2;
  }

  get isChangeRequestStepThree() {
    return this.changeRequestStep === 3;
  }

  get isChangeRequestStepFour() {
    return this.changeRequestStep === 4;
  }

  get isFirstChangeRequestStep() {
    return this.changeRequestStep === 1;
  }

  get isFinalChangeRequestStep() {
    return this.changeRequestStep === 4;
  }

  get nextChangeRequestDisabled() {
    return this.isChangeRequestStepThree && !this.hasSelectedApprovers;
  }

  async loadData() {
    this.errorMessage = "";
    try {
      if (this.testDataMode) {
        this.forecastSections = mockSections();
        this.actualSections = mockSections();
      } else {
        const [forecast, actuals] = await Promise.all([
          getForecastData({ initiativeId: this.recordId }),
          getActualData({ initiativeId: this.recordId })
        ]);
        this.forecastSections = normalizeRows(forecast);
        this.actualSections = normalizeRows(actuals);
      }
      this.initiativePositionAdjustment =
        this.forecastSections?.[0]?.initiativePositionAdjustment ||
        this.actualSections?.[0]?.initiativePositionAdjustment ||
        this.initiativePositionAdjustment;
      this.savedForecastSections = clone(this.forecastSections);
      this.savedActualSections = clone(this.actualSections);
    } catch (error) {
      this.handleError(error);
    }
    this.notifyUnsavedChanges();
  }

  handleTabActive(event) {
    this.activeTab = event.target.value;
  }

  async handleTestModeToggle(event) {
    this.testDataMode = event.target.checked;
    await this.loadData();
  }

  handleEdit() {
    if (this.isForecastTab) {
      this.forecastEditMode = true;
    } else {
      this.actualsEditMode = true;
    }
    this.notifyUnsavedChanges();
  }

  handleReportActuals() {
    // Open only the flow-based Report Actuals modal.
    this.showChangeRequestModal = false;
    this.showFunctionModal = false;
    this.showOperationModal = false;
    this.showCreateApprovalModal = true;
  }

  get flowInputVariables() {
    return [
      {
        name: "recordId",
        type: "String",
        value: this.recordId
      }
    ];
  }

  closeCreateApprovalModal() {
    this.showCreateApprovalModal = false;
  }

  handleCloseCreateInitiativeModal() {
    this.closeCreateApprovalModal();
  }

  handleFlowStatusChange(event) {
    const status = event.detail?.status;
    if (
      status === "FINISHED" ||
      status === "FINISHED_SCREEN" ||
      status === "ERROR"
    ) {
      this.closeCreateApprovalModal();
    }
  }

  closeChangeRequestModal() {
    this.showChangeRequestModal = false;
    this.changeRequestStep = 1;
    this.selectedApproverIds = [];
  }

  handleReportingMonthChange(event) {
    this.selectedReportingMonth = event.target.value;
  }

  handleApproverSelect(event) {
    this.selectedApproverIds = this.toggleSelection(
      this.selectedApproverIds,
      event.target.dataset.id,
      event.target.checked
    );
  }

  handleChangeRequestNext() {
    if (this.nextChangeRequestDisabled) {
      return;
    }
    this.changeRequestStep = Math.min(this.changeRequestStep + 1, 4);
  }

  handleChangeRequestPrevious() {
    this.changeRequestStep = Math.max(this.changeRequestStep - 1, 1);
  }

  submitChangeRequest() {
    const approverNames = this.selectedApprovers.map((approver) => approver.name).join(", ");
    const adjustmentsSubmitted = this.changeRequestSummaryRows.reduce(
      (sum, row) => sum + row.total,
      0
    );
    const nextNumber = this.changeRequests.length + 4052;
    this.changeRequests = [
      {
        id: `mock-cr-${Date.now()}`,
        name: `CR-${nextNumber}`,
        dateSubmitted: new Date().toLocaleDateString("en-US"),
        status: "Pending",
        adjustmentsSubmitted,
        approvers: approverNames,
        comments: ""
      },
      ...this.changeRequests
    ];
    this.closeChangeRequestModal();
    this.toast("Change Request successfully submitted", "", "success");
  }

  handleCancel() {
    this.forecastSections = clone(this.savedForecastSections);
    this.actualSections = clone(this.savedActualSections);
    this.forecastEditMode = false;
    this.actualsEditMode = false;
    this.errorMessage = "";
    this.notifyUnsavedChanges();
  }

  async handleSave() {
    try {
      this.errorMessage = "";
      const sections = this.isForecastTab ? this.forecastSections : this.actualSections;
      this.validateEffectiveTotal(sections);
      if (this.testDataMode) {
        this.savedForecastSections = clone(this.forecastSections);
        this.savedActualSections = clone(this.actualSections);
      } else if (this.isForecastTab) {
        this.forecastSections = normalizeRows(
          await saveForecastData({
            initiativeId: this.recordId,
            wrapperJson: JSON.stringify({ sections: this.forecastSections })
          })
        );
        this.actualSections = normalizeRows(await getActualData({ initiativeId: this.recordId }));
        this.savedForecastSections = clone(this.forecastSections);
        this.savedActualSections = clone(this.actualSections);
      } else {
        this.actualSections = normalizeRows(
          await saveActualData({
            initiativeId: this.recordId,
            wrapperJson: JSON.stringify({ sections: this.actualSections })
          })
        );
        this.savedActualSections = clone(this.actualSections);
      }
      this.forecastEditMode = false;
      this.actualsEditMode = false;
      this.toast("Saved", `${this.activeTitle} values saved.`, "success");
    } catch (error) {
      this.errorMessage = this.getErrorMessage(error);
    }
    this.notifyUnsavedChanges();
    return !this.errorMessage;
  }

  @api
  async save() {
    return this.handleSave();
  }

  @api
  async discard() {
    this.forecastEditMode = false;
    this.actualsEditMode = false;
    this.errorMessage = "";
    await this.loadData();
  }

  notifyUnsavedChanges() {
    const hasUnsaved = this.hasUnsavedChanges;
    if (hasUnsaved === this._lastUnsavedState) {
      return;
    }
    this._lastUnsavedState = hasUnsaved;
    this.dispatchEvent(
      new CustomEvent("unsavedchangeschange", {
        detail: { hasUnsavedChanges: hasUnsaved, label: UNSAVED_CHANGES_LABEL }
      })
    );
  }

  async openFunctionModal() {
    try {
      if (!this.canAddFunctions) {
        this.toast("Add Functions unavailable", this.childInitiativeMessage, "info");
        return;
      }
      this.selectedFunctionIds = [];
      clearTimeout(this.functionSearchDebounce);
      this.functionSearchTerm = "";
      await this.loadAvailableFunctions();
      this.showFunctionModal = true;
    } catch (error) {
      this.handleError(error);
    }
  }

  closeFunctionModal() {
    this.showFunctionModal = false;
    this.selectedFunctionIds = [];
    this.functionSearchTerm = "";
    clearTimeout(this.functionSearchDebounce);
  }

  async loadAvailableFunctions() {
    this.availableFunctions = this.testDataMode
      ? clone(MOCK_AVAILABLE_FUNCTIONS)
      : (await getAvailablePlantFunctions({ initiativeId: this.recordId })).map(this.withUid);
  }

  async refreshAvailableFunctions() {
    try {
      clearTimeout(this.functionSearchDebounce);
      this.functionSearchTerm = "";
      await this.loadAvailableFunctions();
    } catch (error) {
      this.handleError(error);
    }
  }

  handleFunctionSearchInput(event) {
    const searchTerm = event.target.value || "";
    clearTimeout(this.functionSearchDebounce);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.functionSearchDebounce = setTimeout(() => {
      this.functionSearchTerm = searchTerm;
    }, FUNCTION_SEARCH_DEBOUNCE_MS);
  }

  handleFunctionSelect(event) {
    this.selectedFunctionIds = this.toggleSelection(
      this.selectedFunctionIds,
      event.target.dataset.id,
      event.target.checked
    );
  }

  addSelectedFunctions() {
    if (!this.selectedFunctionIds.length) {
      return;
    }
    const rows = this.availableFunctions
      .filter((item) => this.selectedFunctionIds.includes(item.uid))
      .map((item) => ({
        ...item,
        uid: item.uid || item.plantFunctionId,
        crew1: 0,
        crew2: 0,
        crew3: 0,
        operations: []
      }));
    this.forecastSections[0].gwbFunctions = [
      ...this.forecastSections[0].gwbFunctions,
      ...clone(rows)
    ];
    this.actualSections[0].gwbFunctions = [
      ...this.actualSections[0].gwbFunctions,
      ...clone(rows)
    ];
    this.forecastSections = normalizeRows(this.forecastSections);
    this.actualSections = normalizeRows(this.actualSections);
    this.closeFunctionModal();
    this.notifyUnsavedChanges();
    this.toast("Added", "Functions added.", "success");
  }

  async openOperationModal(event) {
    try {
      this.operationContext = {
        sectionIndex: Number(event.currentTarget.dataset.sectionIndex),
        functionUid: event.currentTarget.dataset.functionId
      };
      const row = this.actualSections[this.operationContext.sectionIndex].gwbFunctions.find(
        (item) => item.uid === this.operationContext.functionUid
      );
      this.selectedOperationIds = [];
      clearTimeout(this.operationSearchDebounce);
      this.operationSearchTerm = "";
      await this.loadAvailableOperations(row);
      this.showOperationModal = true;
    } catch (error) {
      this.handleError(error);
    }
  }

  closeOperationModal() {
    this.showOperationModal = false;
    this.selectedOperationIds = [];
    this.operationSearchTerm = "";
    clearTimeout(this.operationSearchDebounce);
    this.operationContext = null;
  }

  async loadAvailableOperations(row) {
    this.availableOperations = this.testDataMode
      ? clone(MOCK_AVAILABLE_OPERATIONS)
      : (await getAvailableOperations({
          initiativeId: this.recordId,
          plantFunctionId: row.plantFunctionId
        })).map(this.withUid);
  }

  async refreshAvailableOperations() {
    try {
      const row = this.actualSections[this.operationContext.sectionIndex].gwbFunctions.find(
        (item) => item.uid === this.operationContext.functionUid
      );
      clearTimeout(this.operationSearchDebounce);
      this.operationSearchTerm = "";
      await this.loadAvailableOperations(row);
    } catch (error) {
      this.handleError(error);
    }
  }

  handleOperationSearchInput(event) {
    const searchTerm = event.target.value || "";
    clearTimeout(this.operationSearchDebounce);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.operationSearchDebounce = setTimeout(() => {
      this.operationSearchTerm = searchTerm;
    }, FUNCTION_SEARCH_DEBOUNCE_MS);
  }

  handleOperationSelect(event) {
    this.selectedOperationIds = this.toggleSelection(
      this.selectedOperationIds,
      event.target.dataset.id,
      event.target.checked
    );
  }

  addSelectedOperations() {
    const row = this.actualSections[this.operationContext.sectionIndex].gwbFunctions.find(
      (item) => item.uid === this.operationContext.functionUid
    );
    row.operations = [
      ...(row.operations || []),
      ...this.availableOperations
        .filter((item) => this.selectedOperationIds.includes(item.uid))
        .map((item) => ({ ...item, crew1: 0, crew2: 0, crew3: 0 }))
    ];
    this.actualSections = normalizeRows(this.actualSections);
    this.closeOperationModal();
    this.notifyUnsavedChanges();
    this.toast("Added", "Operations added.", "success");
  }

  handleCrewChange(event) {
    try {
      const sectionIndex = Number(event.target.dataset.sectionIndex);
      const functionUid = event.target.dataset.functionId;
      const operationUid = event.target.dataset.operationId;
      const field = event.target.dataset.field;
      const value = toInt(event.target.value);
      const sections = clone(this.activeSections);
      const row = sections[sectionIndex].gwbFunctions.find(
        (item) => item.uid === functionUid
      );
      if (operationUid) {
        const operation = row.operations.find((item) => item.uid === operationUid);
        operation[field] = value;
      } else {
        row[field] = value;
      }
      this.errorMessage = "";
      const normalized = normalizeRows(sections);
      if (this.isForecastTab) {
        this.forecastSections = normalized;
      } else {
        this.actualSections = normalized;
      }
      this.notifyUnsavedChanges();
    } catch (error) {
      this.handleError(error);
    }
  }

  validateEffectiveTotal(sections) {
    if ((sections?.[0]?.totalAdjustments || 0) !== this.initiativePositionAdjustment) {
      throw new Error(MISMATCH);
    }
  }

  isCrewDisabled(row, section, crewIndex, operationLevel) {
    if (!section.editable || !this.isEditMode || this.isActualsLockedByChangeRequest) {
      return true;
    }
    if (
      this.isActualsTab &&
      !operationLevel &&
      ((row.operations || []).length > 0 || row.hasActiveOperations)
    ) {
      return true;
    }
    return false;
  }

  toggleSelection(values, id, checked) {
    return checked
      ? [...new Set([...values, id])]
      : values.filter((value) => value !== id);
  }

  withUid(item) {
    return {
      ...item,
      uid: item.uid || item.plantFunctionId || item.operationId || item.id
    };
  }

  handleError(error) {
    const message = this.getErrorMessage(error);
    this.errorMessage = message;
    this.toast("We hit a snag.", message, "error");
  }

  dismissError() {
    this.errorMessage = "";
  }

  getErrorMessage(error) {
    return error?.body?.message || error?.message || "Unexpected error.";
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}