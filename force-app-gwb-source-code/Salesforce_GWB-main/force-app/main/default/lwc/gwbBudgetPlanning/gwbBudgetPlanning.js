/**
 * @description  GWB Budget Planning table component.
 *               Displays volume drivers and MANPOWER headcount rows across
 *               Prev Dec + Jan-Dec. Prev Dec is read-only, Jan-Dec are editable,
 *               and Total Year / Average HC are calculated read-only columns.
 * @group        GWB Budget
 * @last modified on  : 03-25-2026
 */
import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COL_COUNT = 13;
const PREV_DEC_INDEX = 0;
const YEAR_MONTH_COUNT = 12;

function buildCells(values, isTotalRow = false) {
    return values.map((value, idx) => ({
        key: `c-${idx}`,
        value,
        editable: !isTotalRow && idx !== PREV_DEC_INDEX,
        cssClass: isTotalRow
            ? 'month-readonly-cell'
            : idx === PREV_DEC_INDEX
                ? 'prev-dec-cell'
                : 'editable-month-cell',
        valueCssClass: isTotalRow ? 'cell-value cell-bold' : 'cell-value'
    }));
}

function sumYearCells(cells) {
    return cells
        .slice(1)
        .reduce((acc, cell) => acc + (Number(cell.value) || 0), 0);
}

function buildManpowerRow(rowKey, type, values, isTotal = false, showGroupLabel = false, showAvg = false) {
    const cells = buildCells(values, isTotal);
    const total = sumYearCells(cells);
    return {
        key: rowKey,
        type,
        typeCssClass: isTotal ? 'row-type-col type-total' : 'row-type-col',
        cells,
        total,
        totalCssClass: isTotal ? 'cell-value cell-bold' : 'cell-value',
        showGroupLabel,
        showAvg,
        avg: showAvg ? Math.round(total / YEAR_MONTH_COUNT) : null,
        isTotal,
        comments: ''
    };
}

export default class GwbBudgetPlanning extends LightningElement {
    @track plantName = '';
    @track mSchedule = '';
    plantId = '';
    @track isSaving = false;
    @track isStatusModalOpen = false;
    @track selectedStatus = '';

    statusOptions = [
        { label: 'Plant Preview', value: 'Plant Preview' },
        { label: 'Ready to Publish', value: 'Ready to Publish' }
    ];

    @track volumeData = {
        numCrews: buildCells([1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2]),
        numShifts: buildCells([1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2]),
        netJph: buildCells([29.8, 29.8, 29.8, 29.8, 29.8, 21.7, 21.7, 21.7, 21.7, 21.7, 21.7, 21.7, 21.7]),
        calcVolume: buildCells([4053, 4530, 4768, 5245, 1430, 4861, 6597, 5208, 5555, 7291, 7638, 5902, 1389]),
        scheduledVol: buildCells([7593, 3894, 4498, 5238, 1339, 2620, 5254, 4169, 4604, 6353, 6682, 4230, 804]),
        scheduledMinusCalc: buildCells([3540, -636, -270, -7, -91, -2241, -1343, -1039, -951, -938, -956, -1672, -585]),
        paidHours: buildCells([8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]),
        availWorkDays: buildCells([17, 19, 20, 22, 20, 20, 21, 22, 21, 20, 22, 17, 17]),
        prodWorkDays: buildCells([17, 19, 20, 22, 6, 14, 19, 15, 16, 21, 22, 17, 4]),
        eqSotDays: buildCells([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    };

    @track volumeComments = {
        numCrews: '',
        numShifts: '',
        netJph: '',
        calcVolume: '',
        scheduledVol: '',
        scheduledMinusCalc: '',
        paidHours: '',
        availWorkDays: '',
        prodWorkDays: '',
        eqSotDays: ''
    };

    @track manpowerGroups = this._buildManpowerGroups();

    get volumeTotals() {
        return {
            numCrews: sumYearCells(this.volumeData.numCrews),
            numShifts: sumYearCells(this.volumeData.numShifts),
            netJph: '',
            calcVolume: sumYearCells(this.volumeData.calcVolume),
            scheduledVol: sumYearCells(this.volumeData.scheduledVol),
            scheduledMinusCalc: sumYearCells(this.volumeData.scheduledMinusCalc),
            paidHours: '',
            availWorkDays: sumYearCells(this.volumeData.availWorkDays),
            prodWorkDays: sumYearCells(this.volumeData.prodWorkDays),
            eqSotDays: ''
        };
    }

    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        if (pageRef?.state) {
            this.plantId = pageRef.state.plantId || '';
            this.plantName = pageRef.state.plantName || '';
            this.mSchedule = pageRef.state.mSchedule || '';
        }
    }

    handleVolumeChange(event) {
        const row = event.target.dataset.row;
        const idx = parseInt(event.target.dataset.idx, 10);
        const value = parseFloat(event.target.value) || 0;

        const updatedCells = [...this.volumeData[row]];
        updatedCells[idx] = { ...updatedCells[idx], value };
        this.volumeData = { ...this.volumeData, [row]: updatedCells };
    }

    handleVolumeCommentChange(event) {
        const row = event.target.dataset.row;
        this.volumeComments = {
            ...this.volumeComments,
            [row]: event.target.value
        };
    }

    handleManpowerChange(event) {
        const groupKey = event.target.dataset.group;
        const rowKey = event.target.dataset.rowkey;
        const idx = parseInt(event.target.dataset.idx, 10);
        const value = parseFloat(event.target.value) || 0;

        this.manpowerGroups = this.manpowerGroups.map((group) => {
            if (group.key !== groupKey) {
                return group;
            }

            const updatedRows = group.rows.map((row) => {
                if (row.key !== rowKey) {
                    return row;
                }

                const cells = row.cells.map((cell, cellIdx) =>
                    cellIdx === idx ? { ...cell, value } : cell
                );
                const total = sumYearCells(cells);
                return {
                    ...row,
                    cells,
                    total,
                    avg: row.showAvg ? Math.round(total / YEAR_MONTH_COUNT) : null
                };
            });

            return { ...group, rows: this._recalcTotalRow(updatedRows) };
        });
    }

    handleManpowerCommentChange(event) {
        const groupKey = event.target.dataset.group;
        const rowKey = event.target.dataset.rowkey;
        const value = event.target.value;

        this.manpowerGroups = this.manpowerGroups.map((group) => {
            if (group.key !== groupKey) {
                return group;
            }

            return {
                ...group,
                rows: group.rows.map((row) =>
                    row.key === rowKey ? { ...row, comments: value } : row
                )
            };
        });
    }

    handleSave() {
        this.isSaving = true;

        setTimeout(() => {
            this.isSaving = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Draft Saved',
                    message: 'Budget draft has been saved successfully.',
                    variant: 'success'
                })
            );
        }, 1500);
    }

    handleOpenStatusModal() {
        this.isStatusModalOpen = true;
    }

    handleCloseStatusModal() {
        this.isStatusModalOpen = false;
        this.selectedStatus = '';
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
    }

    handleSubmitStatusChange() {
        if (!this.selectedStatus) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Select a Status',
                    message: 'Please select a status before continuing.',
                    variant: 'error'
                })
            );
            return;
        }

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Status Updated',
                message: `Status changed to ${this.selectedStatus}.`,
                variant: 'success'
            })
        );

        this.handleCloseStatusModal();
    }

    _buildManpowerGroups() {
        const zeros = () => new Array(COL_COUNT).fill(0);

        const baseHCOts = buildManpowerRow('baseHC-ots', 'OTS', [768, 797, 797, 779, 779, 1384, 1188, 1135, 1135, 1085, 1085, 1085, 1081], false, true, false);
        const baseHCSkill = buildManpowerRow('baseHC-skill', 'Skilled', [182, 182, 182, 182, 182, 189, 184, 184, 184, 184, 184, 184, 184]);
        const baseHCSal = buildManpowerRow('baseHC-sal', 'Salary', [191, 203, 203, 203, 203, 209, 205, 205, 205, 205, 205, 205, 205]);
        const baseHCTotal = this._computeTotalRow('baseHC-total', [baseHCOts, baseHCSkill, baseHCSal], true);

        return [
            {
                key: 'baseHC',
                label: 'Base Headcount (non SUPP, no Apprentices)',
                rows: [baseHCOts, baseHCSkill, baseHCSal, baseHCTotal]
            },
            {
                key: 'approvedTarget',
                label: '2025 Approved Target Changes',
                rows: [
                    buildManpowerRow('approvedTarget-ots', 'OTS', zeros(), false, true, false),
                    buildManpowerRow('approvedTarget-skill', 'Skilled', zeros()),
                    buildManpowerRow('approvedTarget-sal', 'Salary', zeros())
                ]
            },
            {
                key: 'productivity',
                label: 'Productivity',
                rows: [
                    buildManpowerRow('productivity-ots', 'OTS', zeros(), false, true, false),
                    buildManpowerRow('productivity-skill', 'Skilled', zeros()),
                    buildManpowerRow('productivity-sal', 'Salary', zeros())
                ]
            },
            {
                key: 'mbc',
                label: 'MBC',
                rows: [
                    buildManpowerRow('mbc-ots', 'OTS', zeros(), false, true, false),
                    buildManpowerRow('mbc-skill', 'Skilled', zeros()),
                    buildManpowerRow('mbc-sal', 'Salary', zeros())
                ]
            },
            {
                key: 'lms',
                label: 'LMS',
                rows: [
                    buildManpowerRow('lms-ots', 'OTS', zeros(), false, true, false),
                    buildManpowerRow('lms-skill', 'Skilled', zeros()),
                    buildManpowerRow('lms-sal', 'Salary', zeros())
                ]
            },
            {
                key: 'opPlan',
                label: 'Op Plan Changes',
                rows: [
                    buildManpowerRow('opPlan-ots', 'OTS', [0, 0, 0, 0, 0, 564, -196, -47, 0, 0, 0, 0, 0], false, true, false),
                    buildManpowerRow('opPlan-skill', 'Skilled', [0, 0, 0, 0, 0, 7, -5, 0, 0, 0, 0, 0, 0]),
                    buildManpowerRow('opPlan-sal', 'Salary', [0, 0, 0, 0, 0, 4, -4, 0, 0, 0, 0, 0, 0])
                ]
            },
            {
                key: 'vacation',
                label: 'Vacation Coverage',
                rows: [
                    buildManpowerRow('vacation-ots', 'OTS', [0, 0, 0, 0, 0, 50, 0, 0, 0, -50, 0, 0, 0], false, true, false),
                    buildManpowerRow('vacation-skill', 'Skilled', zeros()),
                    buildManpowerRow('vacation-sal', 'Salary', zeros())
                ]
            },
            {
                key: 'contentChanges',
                label: 'Content changes',
                rows: [
                    buildManpowerRow('contentChanges-ots', 'OTS', [0, 9, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0], false, true, false),
                    buildManpowerRow('contentChanges-skill', 'Skilled', zeros()),
                    buildManpowerRow('contentChanges-sal', 'Salary', [0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
                ]
            }
        ];
    }

    _computeTotalRow(rowKey, sourceRows, showAvg) {
        const cells = sourceRows[0].cells.map((_, idx) => {
            const value = sourceRows.reduce(
                (acc, row) => acc + (Number(row.cells[idx].value) || 0),
                0
            );

            return {
                key: `${rowKey}-c-${idx}`,
                value,
                editable: false,
                cssClass: 'month-readonly-cell',
                valueCssClass: 'cell-value cell-bold'
            };
        });

        const total = sumYearCells(cells);
        return {
            key: rowKey,
            type: 'Total',
            typeCssClass: 'row-type-col type-total',
            cells,
            total,
            totalCssClass: 'cell-value cell-bold',
            showGroupLabel: false,
            showAvg,
            avg: showAvg ? Math.round(total / YEAR_MONTH_COUNT) : null,
            isTotal: true,
            comments: ''
        };
    }

    _recalcTotalRow(rows) {
        const totalRowIndex = rows.findIndex((row) => row.isTotal);
        if (totalRowIndex === -1) {
            return rows;
        }

        const sourceRows = rows.filter((row) => !row.isTotal);
        const currentTotalRow = rows[totalRowIndex];
        const newTotalRow = this._computeTotalRow(
            currentTotalRow.key,
            sourceRows,
            currentTotalRow.showAvg
        );

        newTotalRow.comments = currentTotalRow.comments;

        const updatedRows = [...rows];
        updatedRows[totalRowIndex] = newTotalRow;
        return updatedRows;
    }
}