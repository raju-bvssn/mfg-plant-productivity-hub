import { LightningElement, api, wire } from 'lwc';
import getApprovalHistory from '@salesforce/apex/InitiativeApprovalHistoryController.getApprovalHistory';

const COLUMNS = [
    { label: '', fieldName: 'rowNumber', type: 'number', initialWidth: 70 },
    { label: 'Approval Step', fieldName: 'stepName', type: 'text' },
    {
        label: 'Date Submitted',
        fieldName: 'actionDate',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    { label: 'Status', fieldName: 'status', type: 'text' },
    {
        label: 'Approvers',
        fieldName: 'assignedToUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'assignedTo' },
            target: '_self'
        }
    },
    { label: 'Comments', fieldName: 'comments', type: 'text' }
];

export default class InitiativeApprovalHistory extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    rows = [];
    isLoading = true;
    hasLoadError = false;

    @wire(getApprovalHistory, { recordId: '$recordId' })
    wiredApprovalHistory({ data, error }) {
        this.isLoading = false;

        if (data) {
            this.rows = data.map((row, index) => ({
                ...row,
                assignedToUrl: row.assignedToId ? `/${row.assignedToId}` : null,
                rowNumber: index + 1,
                rowKey: row.id || `${index}`
            }));
            this.hasLoadError = false;
            return;
        }

        this.rows = [];
        this.hasLoadError = Boolean(error);
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get showApprovalHistory() {
        return this.isLoading || this.hasRows;
    }
}