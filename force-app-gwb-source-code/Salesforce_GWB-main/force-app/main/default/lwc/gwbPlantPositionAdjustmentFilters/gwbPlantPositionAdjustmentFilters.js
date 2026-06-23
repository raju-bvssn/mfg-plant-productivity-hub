import { LightningElement, api } from 'lwc';

export default class GwbPlantPositionAdjustmentFilters extends LightningElement {
    @api monthOptions = [];
    @api classificationOptions = [];
    @api driverOptions = [];
    @api balanceStatusOptions = [];
    @api selectedMonth = 'All';
    @api selectedClassification = 'All';
    @api selectedDriver = 'All';
    @api selectedBalanceStatus = 'All';
    @api showBalanceStatusFilter = false;
    @api disabled = false;

    get isBalanceStatusMismatchOnly() {
        return this.selectedBalanceStatus === 'Mismatched Only';
    }

    get balanceStatusSwitchClass() {
        return this.isBalanceStatusMismatchOnly
            ? 'filter-grid__status-switch filter-grid__status-switch_active'
            : 'filter-grid__status-switch';
    }

    handleChange(event) {
        const field = event.target.name;
        const value = event.target.value;

        const detail = {
            month: field === 'month' ? value : this.selectedMonth,
            classification: field === 'classification' ? value : this.selectedClassification,
            driver: field === 'driver' ? value : this.selectedDriver,
            balanceStatus: field === 'balanceStatus' ? value : this.selectedBalanceStatus
        };

        this.dispatchEvent(
            new CustomEvent('filterschange', {
                detail,
                bubbles: true,
                composed: true
            })
        );
    }

    handleBalanceStatusToggle(event) {
        event.preventDefault();
        const detail = {
            month: this.selectedMonth,
            classification: this.selectedClassification,
            driver: this.selectedDriver,
            balanceStatus: this.isBalanceStatusMismatchOnly ? 'All' : 'Mismatched Only'
        };

        this.dispatchEvent(
            new CustomEvent('filterschange', {
                detail,
                bubbles: true,
                composed: true
            })
        );
    }

    handleReset() {
        this.dispatchEvent(
            new CustomEvent('resetfilters', {
                bubbles: true,
                composed: true
            })
        );
    }
}