import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getRecordContext from '@salesforce/apex/ZaptiloSendController.getRecordContext';
import getTemplates from '@salesforce/apex/ZaptiloSendController.getTemplates';
import sendTemplate from '@salesforce/apex/ZaptiloSendController.sendTemplate';

export default class ZaptiloSendModal extends LightningElement {
    @api recordId;

    @track loading = true;
    @track sending = false;
    @track context;
    @track templates = [];
    @track selectedTemplate = '';
    @track language = 'en';
    @track variables = {};
    @track errorMessage = '';

    connectedCallback() {
        // eslint-disable-next-line no-console
        console.log('[Zaptilo] modal opened, recordId=', this.recordId);
        this.bootstrap();
    }

    async bootstrap() {
        if (!this.recordId) {
            this.errorMessage = 'No record id was passed to the Send WhatsApp action.';
            this.loading = false;
            return;
        }
        try {
            // eslint-disable-next-line no-console
            console.log('[Zaptilo] loading record context…');
            this.context = await getRecordContext({ recordId: this.recordId });
            // eslint-disable-next-line no-console
            console.log('[Zaptilo] context=', JSON.stringify(this.context));
            try {
                const raw = await getTemplates();
                // eslint-disable-next-line no-console
                console.log('[Zaptilo] templates count=', (raw || []).length);
                this.templates = (raw || []).map((t) => ({
                    label: `${t.name} (${t.language || 'en'})`,
                    value: t.name,
                    language: t.language || 'en'
                }));
            } catch (e) {
                this.errorMessage = 'Could not load templates: ' + this.errMsg(e);
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[Zaptilo] bootstrap error', e);
            this.errorMessage = this.errMsg(e);
        } finally {
            this.loading = false;
        }
    }

    get templateOptions() {
        return this.templates;
    }

    get canSend() {
        return (
            !this.sending &&
            this.context &&
            this.context.phone &&
            !this.context.optedOut &&
            this.selectedTemplate
        );
    }

    get sendDisabled() {
        return !this.canSend;
    }

    get sendButtonLabel() {
        return this.sending ? 'Sending…' : 'Send WhatsApp';
    }

    get optedOutMessage() {
        if (!this.context) return null;
        if (this.context.optedOut) {
            return `${this.context.name} has Do Not WhatsApp checked. Uncheck the field on the record to enable sending.`;
        }
        if (!this.context.phone) {
            return `${this.context.name} has no phone number on file. Add a phone or mobile to enable sending.`;
        }
        return null;
    }

    handleTemplateChange(event) {
        this.selectedTemplate = event.detail.value;
        const t = this.templates.find((x) => x.value === this.selectedTemplate);
        if (t) this.language = t.language;
        this.variables = {};
    }

    handleVariableChange(event) {
        const idx = event.target.dataset.index;
        this.variables = { ...this.variables, [idx]: event.target.value };
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSend() {
        if (!this.canSend) return;
        this.sending = true;
        try {
            await sendTemplate({
                recordId: this.recordId,
                templateName: this.selectedTemplate,
                language: this.language,
                variables: this.variables
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'WhatsApp sent',
                    message: `Sent ${this.selectedTemplate} to ${this.context.name}.`,
                    variant: 'success'
                })
            );
            this.handleClose();
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Send failed',
                    message: this.errMsg(e),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.sending = false;
        }
    }

    errMsg(e) {
        return e?.body?.message || e?.message || 'Unknown error';
    }
}
