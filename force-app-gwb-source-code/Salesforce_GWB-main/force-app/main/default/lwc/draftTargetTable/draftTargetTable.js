import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import targetGenerationComponentTitle from '@salesforce/label/c.Target_Generation_Component_Title';
import getPlantSectorRows from '@salesforce/apex/DraftTargetController.getPlantSectorRows';
import getMScheduleOptions from '@salesforce/apex/DraftTargetController.getMScheduleOptions';
import getPlantOptions from '@salesforce/apex/DraftTargetController.getPlantOptions';
import getPlantProgramOptions from '@salesforce/apex/DraftTargetController.getPlantProgramOptions';
import getPartTypeOptions from '@salesforce/apex/DraftTargetController.getPartTypeOptions';
import getFunctionalAreaOptions from '@salesforce/apex/DraftTargetController.getFunctionalAreaOptions';
import getTargetYearContext from '@salesforce/apex/DraftTargetController.getTargetYearContext';
import enqueueDraftTargets from '@salesforce/apex/DraftTargetController.enqueueDraftTargets';
import enqueueCloneDraftTargets from '@salesforce/apex/DraftTargetController.enqueueCloneDraftTargets';
import createPlantSector from '@salesforce/apex/DraftTargetController.createPlantSector';
import getTargetStatusUpdateOptions from '@salesforce/apex/DraftTargetController.getTargetStatusUpdateOptions';
import getTargetStatusOrder from '@salesforce/apex/DraftTargetController.getTargetStatusOrder';
import updateTargetStatuses from '@salesforce/apex/DraftTargetController.updateTargetStatuses';
import publishSelectedTargets from '@salesforce/apex/DraftTargetController.publishSelectedTargets';

export default class DraftTargetTable extends NavigationMixin(LightningElement) {
    labels = {
        targetGenerationComponentTitle
    };

    @api recordId;
    @track rows = [];
    @track isLoading = true;
    @track isModalOpen = false;
    @track isProcessingModalOpen = false;
    @track isAddingRow = false;
    @track isSavingNewRow = false;
    @track isUpdateStatusOpen = false;
    @track isUpdatingStatus = false;
    @track isPublishing = false;
    @track selectedUpdateStatus = '';
    @track selectedMSchedule = '';
    @track activeModalAction = 'create';
    @track skippedPublishedNames = [];

    @track newRow = {
        plantId: '',
        region: '',
        plantProgramId: '',
        programCode: '',
        partType: '',
        functionalArea: ''
    };
    @track filters = {
        region: '',
        plant: '',
        sector: 'Assembly',
        mSchedule: '',
        status: ''
    };

    // Target-year context from server (all date/window logic driven by Apex + metadata)
    targetYear = '';
    isNewWindowOpen = false;
    isSystemAdmin = false;
    @track isHiddenWindow = false;
    isPlantScopedUser = false;
    isPlantAdminLikeUser = false;
    isIndustrialEngineerUser = false;
    isPlantViewerUser = false;

    // When hosted on a Plant__c record page, Salesforce provides `recordId`.
    connectedCallback() {
        if (this.recordId) {
            this.filters = {
                ...this.filters,
                plant: this.recordId
            };
        }
        // Imperative call so result is never served from stale wire cache
        // (user permissions can change mid-session when PSGs are assigned)
        getTargetYearContext()
            .then(data => {
                if (data) {
                    this.targetYear = data.targetYear || '';
                    this.isNewWindowOpen = data.isNewWindowOpen || false;
                    this.isSystemAdmin = data.isSystemAdmin || false;
                    this.isHiddenWindow = data.isHiddenWindow || false;
                    this.isPlantScopedUser = data.isPlantScopedUser || false;
                    this.isPlantAdminLikeUser = data.isPlantAdminLikeUser || false;
                    this.isIndustrialEngineerUser = data.isIndustrialEngineerUser || false;
                    this.isPlantViewerUser = data.isPlantViewerUser || false;
                }
            })
            .catch(() => {
                this.targetYear = '';
                this.isNewWindowOpen = false;
                this.isSystemAdmin = false;
                this.isHiddenWindow = false;
                this.isPlantScopedUser = false;
                this.isPlantAdminLikeUser = false;
                this.isIndustrialEngineerUser = false;
                this.isPlantViewerUser = false;
            });
    }

    mScheduleOptions = [];
    plantPickerOptions = [];
    plantProgramOptions = [];
    partTypeOptions = [];
    functionalAreaOptions = [];
    plantOptionsById = {};
    plantProgramsById = {};
    wiredRowsResult;
    statusUpdateOptions = [];
    statusOrder = [];

    @wire(getTargetStatusUpdateOptions)
    wiredTargetStatusUpdateOptions({ data, error }) {
        if (data) {
            this.statusUpdateOptions = data.map((opt) => ({
                label: opt.label,
                value: opt.value
            }));
        } else if (error) {
            this.statusUpdateOptions = [];
        }
    }

    @wire(getTargetStatusOrder)
    wiredTargetStatusOrder({ data, error }) {
        if (data) {
            this.statusOrder = data;
        } else if (error) {
            this.statusOrder = [];
        }
    }

    @wire(getPlantSectorRows)
    wiredRows(result) {
        this.wiredRowsResult = result;
        const { data, error } = result;
        if (data) {
            this.rows = data.map((row) => this.normalizeGroup(row));
            this.isLoading = false;
        } else if (error) {
            this.isLoading = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading plant sectors',
                    message: error.body?.message || 'Unable to load plant sectors.',
                    variant: 'error'
                })
            );
        }
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

    @wire(getPlantOptions)
    wiredPlantOptions({ data, error }) {
        if (data) {
            this.plantPickerOptions = data.map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.plantOptionsById = data.reduce((accumulator, option) => {
                accumulator[option.value] = option;
                return accumulator;
            }, {});
        } else if (error) {
            this.plantPickerOptions = [];
            this.plantOptionsById = {};
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading plants',
                    message: error.body?.message || 'Unable to load plants.',
                    variant: 'error'
                })
            );
        }
    }

    @wire(getFunctionalAreaOptions)
    wiredFunctionalAreaOptions({ data, error }) {
        if (data) {
            this.functionalAreaOptions = data;
        } else if (error) {
            this.functionalAreaOptions = [];
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading Functional Areas',
                    message: error.body?.message || 'Unable to load Functional Area values.',
                    variant: 'error'
                })
            );
        }
    }

    // ─── Basic counts / states ────────────────────────────────────────────────
    get hasRows() {
        return this.rows.length > 0 || this.isAddingRow;
    }

    get selectedParentCount() {
        return this.selectedParentRows.length;
    }

    get hasSkippedTargets() {
        return this.skippedPublishedNames.length > 0;
    }

    get skippedTargetsBannerMessage() {
        return (
            'You have selected Published/Locked Targets and hence update will be skipped for them: ' +
            this.skippedPublishedNames.join(', ')
        );
    }

    get selectedParentRows() {
        return this.rows.filter((row) => row.selected);
    }

    // ─── "New" button ─────────────────────────────────────────────────────────
    // Disabled if:
    //   - outside the generation window (May–Jan 31) AND user is not a system admin, OR
    //   - no parent rows are selected, OR
    //   - any selected parent already has targets linked (clone must be used instead)
    get isCreateDisabled() {
        if (this.isPlantScopedUser) {
            return true;
        }
        if (!this.isNewWindowOpen && !this.isSystemAdmin) {
            return true;
        }
        const selected = this.selectedParentRows;
        if (selected.length < 1) {
            return true;
        }
        return selected.some((row) => row.targets && row.targets.length > 0);
    }

    get isSaveNewRowDisabled() {
        return this.isSavingNewRow || !this.newRow.plantId;
    }

    // ─── Clone button ─────────────────────────────────────────────────────────
    // Enabled only when:
    //   - at least 1 child target is selected
    //   - no plant has more than 1 child selected (exactly 1 per plant)
    get isCloneDisabled() {
        if (this.isPlantScopedUser) {
            return true;
        }
        const anyMultiplePerPlant = this.rows.some(
            (row) => row.targets.filter((t) => t.selected).length > 1
        );
        if (anyMultiplePerPlant) return true;
        return this.selectedCloneTargetIds.length < 1;
    }

    // ─── Update Status button ─────────────────────────────────────────────────
    // Same single-per-plant logic as Clone
    get isUpdateStatusDisabled() {
        if (this.isPlantScopedUser) return true;
        if (this.isUpdatingStatus) return true;
        const anyMultiplePerPlant = this.rows.some(
            (row) => row.targets.filter((t) => t.selected).length > 1
        );
        if (anyMultiplePerPlant) return true;
        return this.selectedTargetIds.length < 1;
    }

    // ─── Publish button ───────────────────────────────────────────────────────
    // Same single-per-plant logic as Clone
    get isPublishDisabled() {
        if (this.isPlantScopedUser) return true;
        if (this.isPublishing) return true;
        const anyMultiplePerPlant = this.rows.some(
            (row) => row.targets.filter((t) => t.selected).length > 1
        );
        if (anyMultiplePerPlant) return true;
        return this.selectedTargetIds.length < 1;
    }

    // All selected child target IDs across all groups
    get selectedTargetIds() {
        return Array.from(
            new Set(
                this.rows.flatMap((row) =>
                    (row.targets || [])
                        .filter((target) => target.selected && target.targetId)
                        .map((target) => target.targetId)
                )
            )
        );
    }

    get selectedCloneTargetIds() {
        return this.selectedTargetIds;
    }

    get showManagementActions() {
        return !this.isPlantScopedUser;
    }

    get isExpanded() {
        return this.rows.some(row => row.isExpanded);
    }

    // ─── GPS / sector display ─────────────────────────────────────────────────
    get showGpsColumns() {
        return this.filters.sector === 'GPS';
    }

    get emptyStateColspan() {
        return this.showGpsColumns ? 6 : 3;
    }

    // ─── Modal helpers ────────────────────────────────────────────────────────
    get modalHeading() {
        return this.activeModalAction === 'clone' ? 'Clone Target' : 'New Target';
    }

    get modalPrimaryLabel() {
        return this.activeModalAction === 'clone' ? 'Clone' : 'Next';
    }

    get modalHelpText() {
        return this.activeModalAction === 'clone'
            ? 'Choose a new M-Schedule to apply to the cloned targets. The M-Schedule must differ from the source.'
            : 'Choose the M-Schedule Data Point for the new draft targets. For GPS plants, Program Code and Functional Area are taken from each selected Plant Sector row.';
    }

    // ─── Visible rows (filtered) ──────────────────────────────────────────────
    get visibleGroups() {
        const hasTargetFilters = Boolean(
            this.filters.mSchedule || this.filters.status
        );

        const filteredRows = this.rows
            .filter((row) => {
                if (this.filters.region && row.region !== this.filters.region) {
                    return false;
                }
                if (this.filters.plant && row.plantId !== this.filters.plant) {
                    return false;
                }
                if (this.filters.sector && row.sector !== this.filters.sector) {
                    return false;
                }
                return true;
            });

        return filteredRows
            .map((row) => {
                const visibleTargets = row.targets.filter((target) => this.matchesTargetFilters(target));
                if (hasTargetFilters && visibleTargets.length === 0) {
                    return null;
                }

                return {
                    ...row,
                    expandIcon: row.isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                    visibleTargets,
                    emptyRowKey: `${row.plantSectorId}-empty`,
                    showNoTargets: row.isExpanded && visibleTargets.length === 0,
                    selectionSummary:
                        visibleTargets.length > 0
                            ? `${visibleTargets.length} target${visibleTargets.length === 1 ? '' : 's'}`
                            : 'No targets'
                };
            })
            .filter((row) => row !== null);
    }

    get visibleSelectableGroups() {
        return this.visibleGroups.filter((row) => !row.checkboxDisabled);
    }

    get isSelectAllDisabled() {
        return this.visibleSelectableGroups.length === 0;
    }

    // Header checkbox is checked only when ALL parents AND ALL their children are selected
    get allVisibleSelectableSelected() {
        return (
            this.visibleSelectableGroups.length > 0 &&
            this.visibleSelectableGroups.every((group) => {
                if (!group.selected) return false;
                return group.visibleTargets.every((target) => target.selected);
            })
        );
    }

    // ─── Filter option builders ───────────────────────────────────────────────
    get regionOptions() {
        return this.buildOptions(this.rows.map((row) => row.region), 'All Regions');
    }

    get plantOptions() {
        const optionsByPlantId = new Map();
        this.rows.forEach((row) => {
            if (row.plantId && !optionsByPlantId.has(row.plantId)) {
                optionsByPlantId.set(row.plantId, {
                    label: row.plantName || row.plantId,
                    value: row.plantId
                });
            }
        });
        return [
            { label: 'All Plants', value: '' },
            ...Array.from(optionsByPlantId.values()).sort((left, right) =>
                left.label.localeCompare(right.label)
            )
        ];
    }

    get filteredPlantPickerOptions() {
        const selectedSector = this.filters.sector;
        if (!selectedSector) {
            return this.plantPickerOptions;
        }
        return this.plantPickerOptions.filter(
            (option) => this.plantOptionsById[option.value]?.sector === selectedSector
        );
    }

    get sectorOptions() {
        return this.buildOptions(this.rows.map((row) => row.sector), 'All Sectors');
    }

    get mScheduleFilterOptions() {
        return this.buildOptions(
            this.rows.flatMap((row) => row.targets.map((target) => target.targetVersion)),
            'All M-Schedules'
        );
    }

    get statusOptions() {
        const values = this.rows.flatMap((row) => row.targets.map((target) => target.targetStatus));
        const uniqueValues = Array.from(new Set(values.filter(Boolean)));
        // Order by the picklist-defined order from GWB_Year__c.Status__c; any unknown statuses sort alphabetically at the end
        const orderedValues = [
            ...this.statusOrder.filter((status) => uniqueValues.includes(status)),
            ...uniqueValues.filter((status) => !this.statusOrder.includes(status)).sort()
        ];
        return [
            { label: 'All Target Statuses', value: '' },
            ...orderedValues.map((value) => ({ label: value, value }))
        ];
    }

    // ─── Selection handlers ───────────────────────────────────────────────────

    // Parent checkbox: selects ONLY the parent row, NOT its children (Rule 4)
    handleParentSelection(event) {
        const groupId = event.target.dataset.id;
        const checked = event.target.checked;
        this.skippedPublishedNames = [];

        this.rows = this.rows.map((row) => {
            if (row.plantSectorId !== groupId) {
                return row;
            }
            return {
                ...row,
                selected: checked
                // Children are NOT auto-selected; they keep their own state
            };
        });
    }

    handleChildSelection(event) {
        const groupId = event.target.dataset.groupId;
        const targetId = event.target.dataset.targetId;
        const checked = event.target.checked;
        this.skippedPublishedNames = [];

        this.rows = this.rows.map((row) => {
            if (row.plantSectorId !== groupId) {
                return row;
            }

            const targets = row.targets.map((target) =>
                target.targetId === targetId ? { ...target, selected: checked } : target
            );

            return {
                ...row,
                targets
            };
        });
    }

    // Header checkbox: selects ALL parents AND ALL their children (Rule 4)
    handleSelectAll(event) {
        const checked = event.target.checked;
        const visibleIds = new Set(this.visibleSelectableGroups.map((row) => row.plantSectorId));
        this.skippedPublishedNames = [];
        this.rows = this.rows.map((row) => {
            if (!visibleIds.has(row.plantSectorId)) {
                return row;
            }
            return {
                ...row,
                selected: checked,
                targets: row.targets.map((target) =>
                    this.matchesTargetFilters(target) ? { ...target, selected: checked } : target
                )
            };
        });
    }

    resetSelections() {
        this.skippedPublishedNames = [];
        this.rows = this.rows.map((row) => ({
            ...row,
            selected: false,
            targets: row.targets.map((target) => ({
                ...target,
                selected: false
            }))
        }));
    }

    handleFilterChange(event) {
        const { name, value } = event.target;
        this.resetSelections();
        this.filters = {
            ...this.filters,
            [name]: value
        };

        if (name === 'sector' && this.isAddingRow) {
            this.handleCancelAddRow();
        }
    }

    handleExpandAll() {
        this.rows = this.rows.map((row) => ({ ...row, isExpanded: true }));
    }

    handleCollapseAll() {
        this.rows = this.rows.map((row) => ({ ...row, isExpanded: false }));
    }

    handleResetFilters() {
        this.resetSelections();
        this.filters = {
            region: '',
            plant: '',
            sector: 'Assembly',
            mSchedule: '',
            status: ''
        };
    }

    toggleGroupExpansion(event) {
        const groupId = event.currentTarget.dataset.id;
        this.rows = this.rows.map((row) =>
            row.plantSectorId === groupId ? { ...row, isExpanded: !row.isExpanded } : row
        );
    }

    // ─── Add-row handlers ─────────────────────────────────────────────────────
    handleStartAddRow() {
        this.isAddingRow = true;
        this.newRow = {
            plantId: '',
            region: '',
            plantProgramId: '',
            programCode: '',
            partType: '',
            functionalArea: ''
        };
        this.plantProgramOptions = [];
        this.partTypeOptions = [];
        this.plantProgramsById = {};
    }

    handleCancelAddRow() {
        this.isAddingRow = false;
        this.isSavingNewRow = false;
        this.newRow = {
            plantId: '',
            region: '',
            plantProgramId: '',
            programCode: '',
            partType: '',
            functionalArea: ''
        };
        this.plantProgramOptions = [];
        this.partTypeOptions = [];
        this.plantProgramsById = {};
    }

    async handleNewRowPlantChange(event) {
        const plantId = event.detail?.recordId || event.detail?.value || '';
        const selectedPlant = this.plantOptionsById[plantId];
        this.newRow = {
            ...this.newRow,
            plantId,
            region: selectedPlant?.region || '',
            plantProgramId: '',
            programCode: '',
            partType: '',
            functionalArea: ''
        };

        this.plantProgramOptions = [];
        this.partTypeOptions = [];
        this.plantProgramsById = {};

        if (!plantId || !this.showGpsColumns) {
            return;
        }

        try {
            const [plantPrograms, partTypes] = await Promise.all([
                getPlantProgramOptions({ plantId }),
                getPartTypeOptions({ plantId })
            ]);

            this.plantProgramOptions = (plantPrograms || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.plantProgramsById = (plantPrograms || []).reduce((accumulator, option) => {
                accumulator[option.value] = option;
                return accumulator;
            }, {});
            this.partTypeOptions = partTypes || [];
        } catch (error) {
            this.plantProgramOptions = [];
            this.partTypeOptions = [];
            this.plantProgramsById = {};
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading plant-specific options',
                    message: error.body?.message || 'Unable to load Plant Program or Part Type values.',
                    variant: 'error'
                })
            );
        }
    }

    async handleNewRowPlantProgramChange(event) {
        const plantProgramId = event.detail?.value || '';
        const selectedProgram = this.plantProgramsById[plantProgramId];

        this.newRow = {
            ...this.newRow,
            plantProgramId,
            programCode: selectedProgram?.programCode || '',
        };

        if (!plantProgramId) {
            return;
        }

    }

    handleNewRowFieldChange(event) {
        const name = event.target.name;
        const value = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        this.newRow = {
            ...this.newRow,
            [name]: value
        };
    }

    async handleSaveNewRow() {
        if (!this.newRow.plantId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Plant required',
                    message: 'Select Plant before saving.',
                    variant: 'error'
                })
            );
            return;
        }

        this.isSavingNewRow = true;
        try {
            const isGpsSector = this.showGpsColumns;
            await createPlantSector({
                plantId: this.newRow.plantId,
                plantProgramId: isGpsSector && this.newRow.plantProgramId ? this.newRow.plantProgramId : null,
                programCode: isGpsSector && this.newRow.programCode ? this.newRow.programCode : null,
                partType: isGpsSector && this.newRow.partType ? this.newRow.partType : null,
                functionalArea: isGpsSector && this.newRow.functionalArea ? this.newRow.functionalArea : null
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Plant Sector created',
                    message: 'The new Plant Sector row was added successfully.',
                    variant: 'success'
                })
            );
            this.handleCancelAddRow();
            await this.handleRefresh();
        } catch (error) {
            this.isSavingNewRow = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error creating Plant Sector',
                    message: error.body?.message || 'Unable to create the Plant Sector row.',
                    variant: 'error'
                })
            );
        }
    }

    // ─── Modal open/close ─────────────────────────────────────────────────────
    handleOpenModal() {
        if (this.selectedParentRows.length < 1) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Select Rows',
                    message: 'Select at least one Plant Sector row to create draft records.',
                    variant: 'error'
                })
            );
            return;
        }

        this.activeModalAction = 'create';
        this.selectedMSchedule = '';
        this.isModalOpen = true;
    }

    handleCloseModal() {
        this.isModalOpen = false;
        this.selectedMSchedule = '';
        this.activeModalAction = 'create';
    }

    handleOpenCloneModal() {
        if (this.selectedCloneTargetIds.length < 1) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Select Targets',
                    message: 'Select at least one target version to clone.',
                    variant: 'error'
                })
            );
            return;
        }

        this.activeModalAction = 'clone';
        this.selectedMSchedule = '';
        this.isModalOpen = true;
    }

    handleCloseProcessingModal() {
        this.isProcessingModalOpen = false;
    }

    async handleRefresh() {
        if (!this.wiredRowsResult) {
            return;
        }

        this.isLoading = true;
        try {
            await refreshApex(this.wiredRowsResult);
        } finally {
            this.isLoading = false;
        }
    }

    handlePlaceholderAction(event) {
        this.handleOpenCloneModal(event);
    }

    // ─── Publish ──────────────────────────────────────────────────────────────
    async handlePublishTargets() {
        if (this.isPublishDisabled) {
            return;
        }

        this.isPublishing = true;
        try {
            const result = await publishSelectedTargets({
                targetIds: this.selectedTargetIds
            });
            const updatedCount = result?.updatedCount || 0;
            const skippedCount = result?.skippedCount || 0;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Publish completed',
                    message:
                        skippedCount > 0
                            ? `Published ${updatedCount} target(s). ${skippedCount} selected target(s) were skipped because they are not in Finance Approved status.`
                            : `Published ${updatedCount} target(s).`,
                    variant: updatedCount > 0 ? 'success' : 'info'
                })
            );
            await this.handleRefresh();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error publishing targets',
                    message: error?.body?.message || error?.message || 'Unable to publish selected targets.',
                    variant: 'error'
                })
            );
        } finally {
            this.isPublishing = false;
        }
    }

    // ─── Update Status ────────────────────────────────────────────────────────
    handleOpenUpdateStatus() {
        if (this.isUpdateStatusDisabled) {
            return;
        }
        this.selectedUpdateStatus = '';
        this.isUpdateStatusOpen = true;
    }

    handleCloseUpdateStatus() {
        this.isUpdateStatusOpen = false;
        this.selectedUpdateStatus = '';
    }

    handleUpdateStatusChange(event) {
        this.selectedUpdateStatus = event.detail.value;
    }

    async handleConfirmUpdateStatus() {
        if (this.isUpdateStatusDisabled) {
            return;
        }
        if (!this.selectedUpdateStatus) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Status required',
                    message: 'Select a status to apply to the selected targets.',
                    variant: 'error'
                })
            );
            return;
        }

        this.isUpdatingStatus = true;
        try {
            const result = await updateTargetStatuses({
                targetIds: this.selectedTargetIds,
                newStatus: this.selectedUpdateStatus
            });

            // Show skipped-targets banner if any were Published/Locked
            if (result?.skippedTargetNames?.length > 0) {
                this.skippedPublishedNames = result.skippedTargetNames;
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Status updated',
                    message: `Updated ${result?.updatedCount || 0} target(s).`,
                    variant: 'success'
                })
            );
            this.handleCloseUpdateStatus();
            await this.handleRefresh();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error updating status',
                    message: error?.body?.message || error?.message || 'Unable to update status.',
                    variant: 'error'
                })
            );
        } finally {
            this.isUpdatingStatus = false;
        }
    }

    handleMScheduleChange(event) {
        this.selectedMSchedule = event.detail.value;
    }

    handleDismissSkippedBanner() {
        this.skippedPublishedNames = [];
    }

    // ─── Create / Clone dispatch ──────────────────────────────────────────────
    async handleCreateDraftTarget() {
        if (!this.selectedMSchedule) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'M-Schedule Required',
                    message: 'Select an M-Schedule Data Point before continuing.',
                    variant: 'error'
                })
            );
            return;
        }

        const selectedRows = this.selectedParentRows;
        const selectedCloneTargetIds = this.selectedCloneTargetIds;
        const selectedMSchedule = this.selectedMSchedule;
        const isCloneAction = this.activeModalAction === 'clone';

        if (isCloneAction ? selectedCloneTargetIds.length < 1 : selectedRows.length < 1) {
            return;
        }

        // Rule 9: Validate the new M-schedule differs from source(s) when cloning
        if (isCloneAction) {
            const sourceMSchedules = Array.from(
                new Set(
                    this.rows.flatMap((row) =>
                        row.targets
                            .filter((t) => t.selected)
                            .map((t) => t.targetVersion)
                    )
                )
            );
            const normalised = selectedMSchedule.replace('%2B', '+');
            if (sourceMSchedules.some((src) => src === normalised || src?.replace('%2B', '+') === normalised)) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Same M-Schedule',
                        message: 'The selected M-Schedule is the same as the source target. Choose a different M-Schedule to clone.',
                        variant: 'error'
                    })
                );
                return;
            }
        }

        try {
            this.isLoading = true;
            if (isCloneAction) {
                const result = await enqueueCloneDraftTargets({
                    targetIds: selectedCloneTargetIds,
                    versionValue: selectedMSchedule
                });

                // Show skipped-targets banner if any were Published/Locked
                if (result?.skippedTargetNames?.length > 0) {
                    this.skippedPublishedNames = result.skippedTargetNames;
                }

                this.selectedMSchedule = '';
                this.activeModalAction = 'create';
                this.isModalOpen = false;
                this.isProcessingModalOpen = true;
                this.rows = this.rows.map((row) => ({
                    ...row,
                    selected: false,
                    targets: row.targets.map((target) => ({ ...target, selected: false }))
                }));
            } else {
                await enqueueDraftTargets({
                    plantSectorIds: selectedRows.map((row) => row.plantSectorId),
                    versionValue: selectedMSchedule
                });
                this.isModalOpen = false;
                this.isProcessingModalOpen = true;
                this.selectedMSchedule = '';
                this.activeModalAction = 'create';
                this.rows = this.rows.map((row) =>
                    row.selected
                        ? {
                              ...row,
                              selected: false,
                              targets: row.targets.map((target) => ({ ...target, selected: false }))
                          }
                        : row
                );
            }
            this.isLoading = false;
        } catch (error) {
            this.isLoading = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: isCloneAction ? 'Error cloning targets' : 'Error creating draft target',
                    message: error.body?.message || (isCloneAction ? 'Unable to clone targets.' : 'Unable to create draft target.'),
                    variant: 'error'
                })
            );
        }
    }

    // ─── Target row navigation ────────────────────────────────────────────────
    handleTargetClick(event) {
        const rowId = event.currentTarget.dataset.groupId;
        const targetId = event.currentTarget.dataset.targetId;
        const selectedRow = this.rows.find((row) => row.plantSectorId === rowId);
        const selectedTarget = selectedRow?.targets.find((target) => target.targetId === targetId);

        if (!selectedRow || !selectedTarget) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: selectedTarget.targetId,
                objectApiName: 'GWB_Year__c',
                actionName: 'view'
            }
        });
    }

    // ─── Normalisation / helpers ──────────────────────────────────────────────
    normalizeGroup(row) {
        return {
            ...row,
            region: row.region || '',
            selected: false,
            isExpanded: false,
            targets: (row.targets || []).map((target) => ({
                ...target,
                rowKey: `${row.plantSectorId}-${target.targetId}`,
                selected: false,
                targetStatusClass: this.buildStatusClass(target.targetStatus),
                targetStatusIcon: this.buildStatusIcon(target.targetStatus),
                targetStatusIconClass: this.buildStatusIconClass(target.targetStatus)
            }))
        };
    }

    matchesTargetFilters(target) {
        if (this.filters.mSchedule && target.targetVersion !== this.filters.mSchedule) {
            return false;
        }
        if (this.filters.status && target.targetStatus !== this.filters.status) {
            return false;
        }
        return true;
    }

    buildStatusClass(statusValue) {
        if (statusValue === 'Draft') return 'status-pill status-pill_draft';
        if (statusValue === 'Plant Review') return 'status-pill status-pill_plant-review';
        if (statusValue === 'Plant Review Complete' || statusValue === 'Plant Review Completed') return 'status-pill status-pill_plant-review-complete';
        if (statusValue === 'Finance Review') return 'status-pill status-pill_finance-review';
        if (statusValue === 'Finance Approved') return 'status-pill status-pill_finance-approved';
        if (statusValue === 'Ready to Publish' || statusValue === 'Ready for Publish') return 'status-pill status-pill_ready';
        if (statusValue === 'Published') return 'status-pill status-pill_published';
        if (statusValue === 'Locked') return 'status-pill status-pill_published';
        return 'status-pill';
    }

    buildStatusIcon(statusValue) {
        if (statusValue === 'Draft') return 'utility:edit';
        if (statusValue === 'Plant Review') return 'custom:custom19';
        if (statusValue === 'Plant Review Complete' || statusValue === 'Plant Review Completed') return 'standard:approval';
        if (statusValue === 'Finance Review') return 'utility:moneybag';
        if (statusValue === 'Finance Approved') return 'standard:approval';
        if (statusValue === 'Published') return 'standard:task2';
        if (statusValue === 'Locked') return 'utility:lock';
        return 'utility:record';
    }

    buildStatusIconClass(statusValue) {
        if (statusValue === 'Draft') return 'status-icon status-icon_draft';
        if (statusValue === 'Plant Review' || statusValue === 'Plant Preview') return 'status-icon status-icon_plant-review';
        if (statusValue === 'Plant Review Complete' || statusValue === 'Plant Review Completed' || statusValue === 'Plant Complete') return 'status-icon status-icon_plant-review-complete';
        if (statusValue === 'Finance Review') return 'status-icon status-icon_finance-review';
        if (statusValue === 'Finance Approved') return 'status-icon status-icon_finance-approved';
        if (statusValue === 'Published') return 'status-icon status-icon_published';
        if (statusValue === 'Locked') return 'status-icon status-icon_published';
        return 'status-icon';
    }

    buildOptions(values, allLabel) {
        const uniqueValues = Array.from(new Set(values.filter(Boolean))).sort();
        return [
            { label: allLabel, value: '' },
            ...uniqueValues.map((value) => ({ label: value, value }))
        ];
    }
}