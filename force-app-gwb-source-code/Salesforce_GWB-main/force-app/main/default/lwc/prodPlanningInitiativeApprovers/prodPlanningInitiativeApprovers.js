import { api, LightningElement, track, wire } from 'lwc';
import hasPlantAdminPermissionFlag from '@salesforce/customPermission/Plant_Admin';
import hasGwbSystemAdminPermissionFlag from '@salesforce/customPermission/GWB_System_Admin';
import {
    FlowAttributeChangeEvent,
    FlowNavigationBackEvent,
    FlowNavigationFinishEvent,
    FlowNavigationNextEvent,
    FlowNavigationPauseEvent
} from 'lightning/flowSupport';
import { RefreshEvent } from 'lightning/refresh';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    refreshTab
} from 'lightning/platformWorkspaceApi';

export default class ProdPlanningInitiativeApprovers extends LightningElement {
    MAX_APPROVERS = 4;
    MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

    @track approvers = [];
    @track selectionErrorMessage = '';
    @api effectiveDate;
    @api Approver_1;
    @api Approver_2;
    @api Approver_3;
    @api Approver_4;
    @api Cancel_Requested;
    @api availableActions = [];
    @track userRecordById = {};
    @track userLookupRecordIds = [];
    approverFieldValues = [null, null, null, null];
    recordPickerDisplayInfo = {
        primaryField: 'Name',
        additionalFields: ['Email']
    };
    recordPickerMatchingInfo = {
        primaryField: { fieldPath: 'Name' },
        additionalFields: [{ fieldPath: 'Email' }]
    };
    baseRecordPickerCriteria = [
        {
            fieldPath: 'IsActive',
            operator: 'eq',
            value: true
        }
    ];
    hasPlantAdminPermission = hasPlantAdminPermissionFlag;
    hasGwbSystemAdminPermission = hasGwbSystemAdminPermissionFlag;
    @wire(IsConsoleNavigation) isConsoleNavigation;

    get canEditPrefilledApprovers() {
        return this.hasPlantAdminPermission || this.hasGwbSystemAdminPermission;
    }

    @api
    set Plant_Approvers(value) {
        this.setApprovers(value);
    }

    get Plant_Approvers() {
        return this.approvers;
    }

    @api
    set approverRecords(value) {
        this.setApprovers(value);
    }

    get approverRecords() {
        return this.approvers;
    }

    @api
    set User_Records(value) {
        const records = Array.isArray(value) ? value : [];
        this.userRecordById = records.reduce((acc, record) => {
            const userId = record.Id || record.ID || record.id;
            const userIdKey = this.toIdKey(userId);
            if (userIdKey) {
                acc[userIdKey] = record;
            }
            return acc;
        }, {});
        this.replaceApproverIdsWithUserNames();
    }

    get User_Records() {
        return Object.values(this.userRecordById);
    }

    @api
    set User_Lookup_Records(value) {
        const records = Array.isArray(value) ? value : [];
        const normalizedIds = records
            .map((record) => this.normalizeId(
                record?.Id
                || record?.ID
                || record?.id
                || record?.UserId
                || record?.User_Id__c
                || record?.Approver_User_Id__c
            ))
            .filter((id) => Boolean(id));

        this.userLookupRecordIds = [...new Set(normalizedIds)];
    }

    get User_Lookup_Records() {
        return this.userLookupRecordIds;
    }

    setApprovers(value) {
        const incoming = Array.isArray(value) ? value : [];
        const normalized = incoming.map((row, index) => {
            const isDefaultApprover = this.toBoolean(row.Default_Approver__c);
            const priorityIndex = this.toPriorityNumber(row.Priority_Index__c);
            const rawApproverValue = row.Approver_User_Id__c || row.Approver_Name__c;
            const approverUserId = this.normalizeId(rawApproverValue);

            if (rawApproverValue && !approverUserId) {
                // Helps identify bad Flow/source data that cannot be used in record picker values.
                // eslint-disable-next-line no-console
                console.warn(
                    '[prodPlanningInitiativeApprovers] Invalid approver ID received from Flow data',
                    {
                        sourceIndex: index,
                        rawApproverValue,
                        row
                    }
                );
            }

            return {
                ...row,
                _sourceIndex: index,
                isDefaultApprover,
                priorityIndex,
                Approver_User_Id__c: approverUserId,
                selected: isDefaultApprover || Boolean(row.selected)
            };
        });

        this.approvers = this.sortApprovers(normalized);
        this.replaceApproverIdsWithUserNames();
        this.prefillApproversFromSortedRecords();
    }

    get selectedCount() {
        return this.approverFieldValues.filter((value) => Boolean(value)).length;
    }

    get recordPickerFilter() {
        const criteria = [...this.baseRecordPickerCriteria];
        if (this.userLookupRecordIds.length > 0) {
            criteria.push({
                fieldPath: 'Id',
                operator: 'in',
                value: this.userLookupRecordIds
            });
        }

        return { criteria };
    }

    get reportTitle() {
        const parsedDate = this.parseFlowDate(this.effectiveDate);
        if (!parsedDate) {
            return 'Reporting Actuals';
        }

        const monthName = this.MONTH_NAMES[parsedDate.month - 1];
        return `Reporting Actuals for ${monthName}, ${parsedDate.year}`;
    }

    get approver1Value() {
        return this.approverFieldValues[0];
    }

    get approver2Value() {
        return this.approverFieldValues[1];
    }

    get approver3Value() {
        return this.approverFieldValues[2];
    }

    get approver4Value() {
        return this.approverFieldValues[3];
    }

    get isApprover1Disabled() {
        return !this.canEditPrefilledApprovers && Boolean(this.approver1Value);
    }

    get isApprover2Disabled() {
        return !this.canEditPrefilledApprovers && Boolean(this.approver2Value);
    }

    get isApprover3Disabled() {
        return !this.canEditPrefilledApprovers && Boolean(this.approver3Value);
    }

    get isApprover4Disabled() {
        return !this.canEditPrefilledApprovers && Boolean(this.approver4Value);
    }

    handleApproverChange(event) {
        const fieldIndex = Number(event.target.dataset.index);
        const selectedRecordId = event.detail?.recordId || null;
        const normalizedId = this.normalizeId(selectedRecordId);

        if (!Number.isInteger(fieldIndex) || fieldIndex < 0 || fieldIndex >= this.MAX_APPROVERS) {
            return;
        }

        if (!this.canEditPrefilledApprovers && Boolean(this.approverFieldValues[fieldIndex])) {
            return;
        }

        this.approverFieldValues = this.approverFieldValues.map((value, index) => (index === fieldIndex ? normalizedId : value));
        this.selectionErrorMessage = this.getSelectionValidationError() || '';
        this.syncApproverOutputs();
    }

    getSelectionValidationError() {
        return this.getSequentialFillError() || this.getDuplicateApproverError();
    }

    getSequentialFillError() {
        let foundEmptyField = false;
        for (let index = 0; index < this.MAX_APPROVERS; index += 1) {
            const hasValue = Boolean(this.approverFieldValues[index]);
            if (!hasValue) {
                foundEmptyField = true;
                continue;
            }

            if (foundEmptyField) {
                return 'Please fill approvers sequentially. Do not skip an approver input.';
            }
        }

        return null;
    }

    getDuplicateApproverError() {
        const selectedIds = this.approverFieldValues.filter((value) => Boolean(value));
        if (selectedIds.length <= 1) {
            return null;
        }

        const uniqueIds = new Set(selectedIds.map((value) => this.toIdKey(value)));
        if (uniqueIds.size !== selectedIds.length) {
            return 'Same user cannot be selected in more than one approver input.';
        }

        return null;
    }

    syncApproverOutputs() {
        const selectedApproverIds = this.approverFieldValues.slice(0, this.MAX_APPROVERS);

        this.updateFlowOutput('Approver_1', selectedApproverIds[0] || null);
        this.updateFlowOutput('Approver_2', selectedApproverIds[1] || null);
        this.updateFlowOutput('Approver_3', selectedApproverIds[2] || null);
        this.updateFlowOutput('Approver_4', selectedApproverIds[3] || null);
        this.updateFlowOutput('Cancel_Requested', this.cancelRequested);
    }

    sortApprovers(rows) {
        return [...rows].sort((a, b) => {
            if (a.isDefaultApprover !== b.isDefaultApprover) {
                return a.isDefaultApprover ? -1 : 1;
            }

            if (a.priorityIndex !== b.priorityIndex) {
                return a.priorityIndex - b.priorityIndex;
            }

            return a._sourceIndex - b._sourceIndex;
        });
    }

    toBoolean(value) {
        return value === true || value === 'true';
    }

    toPriorityNumber(value) {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : Number.MAX_SAFE_INTEGER;
    }

    getApproverName(row) {
        return row.Approver_Name__c || row.approverName || row.name || row.Name || null;
    }

    getApproverOutputId(row) {
        const userRecord = this.getUserRecordByApprover(row);
        const userRecordId = userRecord?.Id || userRecord?.ID || userRecord?.id;
        return this.normalizeId(userRecordId || row.Approver_User_Id__c);
    }

    getApproverUserId(row) {
        return row.Approver_User_Id__c || this.normalizeId(row.Approver_Name__c || null);
    }

    getUserRecordByApprover(row) {
        const approverUserId = this.getApproverUserId(row);
        const approverUserIdKey = this.toIdKey(approverUserId);
        return approverUserIdKey ? this.userRecordById[approverUserIdKey] : null;
    }

    getDisplayName(row) {
        return row.Approver_Name__c || row.name || row.Name || '';
    }

    getDisplayDepartment(row) {
        const userRecord = this.getUserRecordByApprover(row);
        return userRecord?.Department || userRecord?.department || '';
    }

    replaceApproverIdsWithUserNames() {
        if (!Array.isArray(this.approvers) || this.approvers.length === 0) {
            return;
        }

        this.approvers = this.approvers.map((row) => {
            const approverUserId = this.normalizeId(row.Approver_User_Id__c || row.Approver_Name__c);
            const approverUserIdKey = this.toIdKey(approverUserId);
            const userRecord = approverUserIdKey ? this.userRecordById[approverUserIdKey] : null;
            return {
                ...row,
                Approver_User_Id__c: approverUserId,
                Approver_Name__c: userRecord?.Name || userRecord?.name || row.Approver_Name__c
            };
        });
    }

    prefillApproversFromSortedRecords() {
        const prefilledIds = this.approvers
            .map((row) => this.getApproverOutputId(row))
            .filter((id) => Boolean(id))
            .slice(0, this.MAX_APPROVERS);

        this.approverFieldValues = [
            prefilledIds[0] || null,
            prefilledIds[1] || null,
            prefilledIds[2] || null,
            prefilledIds[3] || null
        ];
        this.syncApproverOutputs();
    }

    updateFlowOutput(attributeName, value) {
        this[attributeName] = value;
        this.dispatchEvent(new FlowAttributeChangeEvent(attributeName, value));
    }

    normalizeId(value) {
        if (!value) {
            return null;
        }

        const idString = String(value).trim();
        if (!idString || !/^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(idString)) {
            return null;
        }

        return idString;
    }

    toIdKey(value) {
        const normalizedId = this.normalizeId(value);
        return normalizedId ? normalizedId.substring(0, 15).toUpperCase() : null;
    }

    parseFlowDate(value) {
        if (!value || typeof value !== 'string') {
            return null;
        }

        const parts = value.split('-');
        if (parts.length !== 3) {
            return null;
        }

        const year = Number(parts[0]);
        const month = Number(parts[1]);
        const day = Number(parts[2]);
        const isValid = Number.isInteger(day)
            && Number.isInteger(month)
            && Number.isInteger(year)
            && day >= 1
            && day <= 31
            && month >= 1
            && month <= 12;

        return isValid ? { day, month, year } : null;
    }

    handleClose() {
        this.handleCancel();
    }

    handlePrevious() {}

    handleCancel() {
        this.Cancel_Requested = true;
        this.syncApproverOutputs();
        this.navigateAfterOutputSync();
    }

    handleSubmitForApproval() {
        if (this.selectedCount === 0) {
            this.selectionErrorMessage = 'Please select at least one approver before submitting.';
            return;
        }

        const validationError = this.getSelectionValidationError();
        if (validationError) {
            this.selectionErrorMessage = validationError;
            return;
        }

        this.selectionErrorMessage = '';
        this.syncApproverOutputs(false);
        if (this.availableActions.includes('NEXT')) {
            this.dispatchEvent(new FlowNavigationNextEvent());
            this.scheduleTabRefresh();
            return;
        }

        if (this.availableActions.includes('FINISH')) {
            this.dispatchEvent(new FlowNavigationFinishEvent());
            this.scheduleTabRefresh();
        }
    }

    scheduleTabRefresh() {
        // Give Flow navigation a moment to process outputs before refreshing the current view.
        setTimeout(() => {
            this.refreshCurrentTabView();
        }, 2000);
    }

    async refreshCurrentTabView() {
        try {
            const focusedTab = await getFocusedTabInfo();
            await refreshTab(focusedTab.tabId, { includeAllSubtabs: true });
            return;
        } catch (error) {
            // Fall through to non-console refresh strategies.
        }

        try {
            this.dispatchEvent(new RefreshEvent());
            return;
        } catch (error) {
            // Final fallback below.
        }

        // Final fallback: reload only the current browser tab.
        window.location.reload();
    }

    navigateAfterOutputSync() {
        // Let Flow process FlowAttributeChangeEvent before navigation.
        setTimeout(() => {
            if (this.availableActions.includes('NEXT')) {
                // Re-emit cancel flag immediately before NEXT to maximize Flow capture reliability.
                this.updateFlowOutput('Cancel_Requested', true);
                this.dispatchEvent(new FlowNavigationNextEvent());
                return;
            }

            if (this.availableActions.includes('FINISH')) {
                this.dispatchEvent(new FlowNavigationFinishEvent());
                return;
            }

            if (this.availableActions.includes('BACK')) {
                this.dispatchEvent(new FlowNavigationBackEvent());
                return;
            }

            if (this.availableActions.includes('PAUSE')) {
                this.dispatchEvent(new FlowNavigationPauseEvent());
            }
        }, 0);
    }
}