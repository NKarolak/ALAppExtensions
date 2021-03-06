codeunit 1083 "MS - Wallet Webhook Management"
{
    Permissions = TableData 1086 = rimd, TableData 2000000199 = rimd;

    var
        WalletCreatedByTok: Label 'PAY.MICROSOFT', Locked = true;
        InvoiceTxtTok: Label 'Invoice ', Locked = true;
        ChargeDescriptionTok: Label 'Payment for %1';
        ChargeAPIURLFormatTok: Label '%1/v1.0/merchants/%2/charges', Locked = true;
        UnexpectedAccountErr: Label 'Merchant ID %1 is unexpected.';
        TelemetryUnexpectedAccountErr: Label 'Unexpected Merchant ID detected.', Locked = true;
        UnexpectedInvoiceNumberErr: Label 'Invoice number ''%1'' is unexpected.';
        TelemetryUnexpectedInvoiceNumberErr: Label 'Invoice with unexpected number detected.', Locked = true;
        UnexpectedInvoiceClosedErr: Label 'Invoice number ''%1'' is already paid.', Locked = true;
        TelemetryUnexpectedInvoiceClosedErr: Label 'Attempted to pay an invoice that is already paid.', Locked = true;
        UnexpectedCurrencyCodeErr: Label 'Currency code %2 is unexpected. Currency Code ''%2'' does not match ''%3''.';
        UnexpectedAmountErr: Label 'Amount ''%1'' is unexpected.';
        TelemetryUnexpectedAmountErr: Label 'Unexpected amount detected.', Locked = true;
        UnexpectedCreateTimeErr: Label 'Create time ''%1'' is unexpected.';
        MSWalletTelemetryCategoryTok: Label 'AL MSPAY', Locked = true;
        MSWalletChargeTelemetryErr: Label 'Error while charging payment token. Response status code %1, Error: %2.', Locked = true;
        MSWalletChargeErr: Label 'Merchant %1: Error while charging payment token. Response status code %2, Error: %3.', Locked = true;
        ChargeJsonTelemetryTxt: Label 'Error, could not construct Json object for charge call.', Locked = true;

        CancellingPaymentTxt: Label 'Error happened while charging the customer; reversing the last payment.', Locked = true;
        CancellingPaymentDoneTxt: Label 'Error happened while charging the customer; reversing the last payment was done successfully.', Locked = true;
        PostingPaymentErr: Label 'Error happened while posting payment against the invoice.';
        ChargeCallErr: Label 'Error happened while charging customer.';
        CancellingPaymentErrorTxt: Label 'Error happened: charge call failed, then could not revert the posted payment.', Locked = true;
        ActivityCancellingPaymentErrTxt: Label 'Error happened: charge call failed, then could not revert the posted payment for invoice %1.', Locked = true;
        MerchantsCustomerPaidTxt: Label 'The payment of the merchant''s customer was successfully processed.', Locked = true;
        NoWebhookSubscriptionTxt: Label 'Webhook subscription could not be found.';
        SetupUserIsDisabledOrDeletedTxt: Label 'The user that was used to set up Microsoft Pay Payments has been deleted or disabled.';
        NoPaymentRegistrationSetupErrTxt: Label 'The Payment Registration Setup window is not filled in correctly for user %1.';
        PaymentRegistrationSetupFieldErrTxt: Label 'The Payment Registration Setup window is not filled in for user %1.';
        CannotMakePaymentWarningTxt: Label 'You may not be able to accept payments throught Microsoft Pay Payments. %1', Comment = '%1 is an error message.';
        SetupDeleteOrDisableWithOpenInvoiceQst: Label 'You have unpaid invoices with a Microsoft Pay Payments link. Deleting or disabling the Microsoft Pay Payments account setup will make you unable to accept payments through Microsoft Pay Payments.\\ Do you want to continue?';
        ChargeRequestFailedResponseTxt: Label 'Error while charging payment token. Response status code %1.', Locked = true;
        ChargeCannotReadResponseTxt: Label 'Cannot read response on charge call.', Locked = true;
        ChargeEmptyResponseTxt: Label 'Empty reponse on charge call.', Locked = true;
        ChargeIncorrectResponseTxt: Label 'Incorrect reponse on charge call.', Locked = true;
        WebhookSubscriptionNotFoundTxt: Label 'Webhook subscription is not found.', Locked = true;
        NoRemainingPaymentsTxt: Label 'The payment is ignored because no payment remains.', Locked = true;
        OverpaymentTxt: Label 'The payment is ignored because of overpayment.', Locked = true;
        ProcessingWebhookNotificationTxt: Label 'Processing webhook notification.', Locked = true;
        RegisteringPaymentTxt: Label 'Registering the payment.', Locked = true;
        PaymentRegistrationSucceedTxt: Label 'Payment registration succeed.', Locked = true;
        EmptyNotificationTxt: Label 'Webhook notification is empty.', Locked = true;
        IncorrectNotificationTxt: Label 'Webhook notification is incorrect.', Locked = true;
        IgnoreNotificationTxt: Label 'Ignore notification.', Locked = true;
        VerifyNotificationContentTxt: Label 'Verify notification content.', Locked = true;
        NotificationContentVerifiedTxt: Label 'Notification content is successfully verified.', Locked = true;
        VerifyTransactionDetailsTxt: Label 'Verify transaction details.', Locked = true;
        TransactionDetailsVerifiedTxt: Label 'Transaction details are successfully verified.', Locked = true;
        SaveChargeResourceTxt: Label 'Save charge resource.', Locked = true;
        CannotParseAmountTxt: Label 'Cannot parse amount.', Locked = true;
        CannotParseCreateTimeTxt: Label 'Cannot parse create time.', Locked = true;
        UnexpectedCurrencyCodeTelemetryTxt: Label 'Unexpected currency code.', Locked = true;
        MSPayContextTxt: Label 'MSPay', Locked = true;

    [EventSubscriber(ObjectType::Table, 2000000194, 'OnAfterInsertEvent', '', false, false)]
    local procedure SyncToNavOnWebhookNotificationInsert(var Rec: Record 2000000194; RunTrigger: Boolean);
    var
        WebhookSubscription: Record 2000000199;
        MSWalletMerchantAccount: Record 1080;
        JObject: JsonObject;
        SubscriptionID: Text[250];
        PaymentToken: Text;
        MerchantID: Text[150];
        InvoiceNoTxt: Text;
        CurrencyCode: Code[10];
        InvoiceNoCode: Code[20];
        TotalAmount: Decimal;
        PayerEmail: Text;
    begin
        SendTraceTag('00008IE', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, ProcessingWebhookNotificationTxt, DataClassification::SystemMetadata);

        SubscriptionID := LOWERCASE(Rec."Subscription ID");
        WebhookSubscription.SetRange("Subscription ID", SubscriptionID);
        WebhookSubscription.SetFilter("Created By", GetCreatedByFilterForWebhooks());
        IF WebhookSubscription.IsEmpty() THEN BEGIN
            SendTraceTag('00008HI', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, WebhookSubscriptionNotFoundTxt, DataClassification::SystemMetadata);
            EXIT;
        END;

        IF NOT GetNotificationJson(Rec, JObject) THEN BEGIN
            SendTraceTag('00008HK', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, IgnoreNotificationTxt, DataClassification::SystemMetadata);
            EXIT;
        END;

        MerchantID := GetMerchantIDFromSubscriptionID(Rec."Subscription ID");

        MSWalletMerchantAccount.SETRANGE("Merchant ID", MerchantID);
        IF NOT MSWalletMerchantAccount.FINDFIRST() THEN BEGIN
            SENDTRACETAG('00001CP', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, TelemetryUnexpectedAccountErr, DataClassification::SystemMetadata);
            LogActivity(StrSubstNo(UnexpectedAccountErr, MerchantID), '');
            ERROR(UnexpectedAccountErr, MerchantID);
        END;

        GetDetailsFromNotification(JObject, InvoiceNoTxt, PaymentToken, CurrencyCode, TotalAmount, PayerEmail);

        IF STRPOS(InvoiceNoTxt, InvoiceTxtTok) = 1 THEN
            InvoiceNoCode := CopyStr(DELSTR(InvoiceNoTxt, 1, STRLEN(InvoiceTxtTok)), 1, MaxStrLen(InvoiceNoCode))
        ELSE
            InvoiceNoCode := COPYSTR(InvoiceNoTxt, 1, MAXSTRLEN(InvoiceNoCode));

        ValidateInvoiceDetails(InvoiceNoCode, TotalAmount, CurrencyCode);

        IF not PostPaymentForInvoice(InvoiceNoCode, TotalAmount) THEN
            Error(PostingPaymentErr);

        IF NOT ChargePaymentNotification(MSWalletMerchantAccount, InvoiceNoTxt, TotalAmount, PaymentToken, CurrencyCode, PayerEmail) THEN begin
            // An error happened while charging the user: reverse the payment posted against the invoice
            if not CancelInvoiceLastPayment(InvoiceNoCode) then begin
                SENDTRACETAG('00001TZ', MSWalletTelemetryCategoryTok, VERBOSITY::Critical, CancellingPaymentErrorTxt, DataClassification::SystemMetadata); // payment has been posted and could not revert it, but user was not charged
                LogActivity(StrSubstNo(ActivityCancellingPaymentErrTxt, InvoiceNoCode), '');
            end;
            Error(ChargeCallErr);
        end;

        SENDTRACETAG('00001V7', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, MerchantsCustomerPaidTxt, DataClassification::SystemMetadata);
    end;

    procedure GetCreatedByFilterForWebhooks(): Text;
    begin
        exit('@*' + WalletCreatedByTok + '*');
    end;

    procedure GetNotificationUrl(): Text[250];
    var
        WebhookManagement: Codeunit 5377;
    begin
        exit(LOWERCASE(WebhookManagement.GetNotificationUrl()));
    end;

    procedure GetWebhookSubscriptionID(AccountID: Text[250]): Text[250];
    begin
        EXIT(CopyStr(LowerCase(StrSubstNo('%1_%2', AccountID, CompanyProperty.UrlName())), 1, 250));
    end;

    procedure GetMerchantIDFromSubscriptionID(SubscriptionID: Text[250]): Text[150];
    var
        SplitIndex: Integer;
    begin
        SplitIndex := SubscriptionID.IndexOf('_');
        if SplitIndex = 0 then
            exit(CopyStr(SubscriptionID, 1, 150));
        exit(CopyStr(SubscriptionID.Substring(1, SplitIndex - 1), 1, 150));
    end;

    procedure PostPaymentForInvoice(InvoiceNo: Code[20]; AmountReceived: Decimal): Boolean;
    var
        TempPaymentRegistrationBuffer: Record 981 temporary;
        PaymentMethod: Record 289;
        PaymentRegistrationMgt: Codeunit 980;
        O365SalesInvoicePayment: Codeunit 2105;
        MSWalletMgt: Codeunit 1080;
    begin
        IF NOT O365SalesInvoicePayment.CollectRemainingPayments(InvoiceNo, TempPaymentRegistrationBuffer) THEN BEGIN
            SendTraceTag('00008HL', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, NoRemainingPaymentsTxt, DataClassification::SystemMetadata);
            EXIT(FALSE);
        END;

        IF TempPaymentRegistrationBuffer."Remaining Amount" >= AmountReceived THEN BEGIN
            SendTraceTag('00008HM', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, RegisteringPaymentTxt, DataClassification::SystemMetadata);
            TempPaymentRegistrationBuffer.VALIDATE("Amount Received", AmountReceived);
            TempPaymentRegistrationBuffer.VALIDATE("Date Received", WORKDATE());
            MSWalletMgt.GetWalletPaymentMethod(PaymentMethod);
            TempPaymentRegistrationBuffer.VALIDATE("Payment Method Code", PaymentMethod.Code);
            TempPaymentRegistrationBuffer.MODIFY(TRUE);
            PaymentRegistrationMgt.Post(TempPaymentRegistrationBuffer, FALSE);
            OnAfterPostWalletPayment(TempPaymentRegistrationBuffer, AmountReceived);
            SendTraceTag('00008ID', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, PaymentRegistrationSucceedTxt, DataClassification::SystemMetadata);
            EXIT(TRUE);
        END;

        SendTraceTag('00008HN', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, OverpaymentTxt, DataClassification::SystemMetadata);
        OnAfterReceiveWalletOverpayment(TempPaymentRegistrationBuffer, AmountReceived);

        EXIT(FALSE);
    end;

    local procedure ChargePaymentNotification(MSWalletMerchantAccount: Record 1080; InvoiceNoTxt: Text; GrossAmount: Decimal; PaymentToken: Text; CurrencyCode: Code[10]; receiptEmail: Text): Boolean;
    var
        MSWalletMgt: Codeunit 1080;
        RequestHttpClient: HttpClient;
        RequestMessage: HttpRequestMessage;
        ResponseMessage: HttpResponseMessage;
        RequestContent: HttpContent;
        RequestHeaders: HttpHeaders;
        ContentHeaders: HttpHeaders;
        JObject: JsonObject;
        AuthHeader: Text;
        RequestPayload: Text;
        JPayload: JsonObject;
        ChargeAPIURL: Text;
    begin
        AuthHeader := MSWalletMgt.GetAADAuthHeader(MSWalletMerchantAccount.GetBaseURL());

        ChargeAPIURL := STRSUBSTNO(ChargeAPIURLFormatTok, MSWalletMerchantAccount.GetBaseURL(), MSWalletMerchantAccount."Merchant ID");

        JPayload.Add('idempotencyKey', CreateGuid());
        JPayload.Add('referenceId', InvoiceNoTxt);
        JPayload.Add('amount', GrossAmount);
        JPayload.Add('currency', CurrencyCode);
        JPayload.Add('paymentToken', PaymentToken);
        JPayload.Add('description', STRSUBSTNO(ChargeDescriptionTok, InvoiceNoTxt));
        JPayload.Add('receiptEmail', receiptEmail);

        if not JPayload.WriteTo(RequestPayload) then begin
            SendTraceTag('00001YC', MSWalletTelemetryCategoryTok, VERBOSITY::Error, ChargeJsonTelemetryTxt, DataClassification::SystemMetadata);
            LogActivity(ChargeJsonTelemetryTxt, '');
        end;

        RequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Add('Authorization', AuthHeader);
        RequestHeaders.Add('MS-AccountMode', GetMSAccountMode(MSWalletMerchantAccount));
        RequestMessage.SetRequestUri(ChargeAPIURL);
        RequestMessage.Method('POST');
        RequestContent.GetHeaders(ContentHeaders);
        RequestContent.WriteFrom(RequestPayload);
        ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json; charset=utf-8');
        RequestMessage.Content(RequestContent);

        if not RequestHttpClient.Send(RequestMessage, ResponseMessage) then begin
            SendTraceTag('00008HO', MSWalletTelemetryCategoryTok, VERBOSITY::Error, StrSubstNo(ChargeRequestFailedResponseTxt, ResponseMessage.HttpStatusCode()),
              DataClassification::SystemMetadata);
            SendTraceTag(
              '00001P6', MSWalletTelemetryCategoryTok, VERBOSITY::Error, STRSUBSTNO(MSWalletChargeTelemetryErr, ResponseMessage.HttpStatusCode(), GETLASTERRORTEXT()),
              DataClassification::CustomerContent);
            LogActivity(STRSUBSTNO(MSWalletChargeErr, MSWalletMerchantAccount."Merchant ID", ResponseMessage.HttpStatusCode(), GETLASTERRORTEXT()), RequestPayload);
            EXIT(FALSE);
        END;

        if GetChargeResource(ResponseMessage, JObject) then
            exit(SaveChargeResource(JObject));

        SendTraceTag(
          '00001P7', MSWalletTelemetryCategoryTok, VERBOSITY::Error, STRSUBSTNO(MSWalletChargeTelemetryErr, ResponseMessage.HttpStatusCode(), ResponseMessage.ReasonPhrase()),
          DataClassification::CustomerContent);
        LogActivity(STRSUBSTNO(MSWalletChargeErr, MSWalletMerchantAccount."Merchant ID", ResponseMessage.HttpStatusCode(), ResponseMessage.ReasonPhrase()), RequestPayload);
        EXIT(FALSE);
    end;

    local procedure GetChargeResource(var ResponseMessage: HttpResponseMessage; var JObject: JsonObject): Boolean;
    var
        ResponseText: Text;
    begin
        if not ResponseMessage.IsSuccessStatusCode() then begin
            SendTraceTag('00008HP', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, StrSubstNo(ChargeRequestFailedResponseTxt, ResponseMessage.HttpStatusCode()),
              DataClassification::SystemMetadata);
            exit(false);
        end;
        if not ResponseMessage.Content().ReadAs(ResponseText) then begin
            SendTraceTag('00008HQ', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, ChargeCannotReadResponseTxt, DataClassification::SystemMetadata);
            exit(false);
        end;
        if ResponseText = '' then begin
            SendTraceTag('00008HR', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, ChargeEmptyResponseTxt, DataClassification::SystemMetadata);
            exit(false);
        end;
        if not JObject.ReadFrom(ResponseText) then begin
            SendTraceTag('00008HS', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, ChargeIncorrectResponseTxt, DataClassification::SystemMetadata);
            exit(false);
        end;
        exit(true);
    end;

    local procedure GetNotificationJson(var WebhookNotification: Record 2000000194; var JObject: JsonObject): Boolean;
    var
        NotificationStream: InStream;
        NotificationString: Text;
    begin
        SendTraceTag('00008HT', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, VerifyNotificationContentTxt, DataClassification::SystemMetadata);

        NotificationString := '';
        WebhookNotification.CALCFIELDS(Notification);
        IF NOT WebhookNotification.Notification.HASVALUE() THEN BEGIN
            SendTraceTag('00008HU', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, EmptyNotificationTxt, DataClassification::SystemMetadata);
            EXIT(FALSE);
        END;

        WebhookNotification.Notification.CREATEINSTREAM(NotificationStream);
        NotificationStream.READ(NotificationString);

        IF NOT JObject.ReadFrom(NotificationString) THEN BEGIN
            SendTraceTag('00008HV', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, IncorrectNotificationTxt, DataClassification::SystemMetadata);
            EXIT(FALSE);
        END;

        SendTraceTag('00008HW', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, NotificationContentVerifiedTxt, DataClassification::SystemMetadata);
        EXIT(TRUE);
    end;

    local procedure GetDetailsFromNotification(var JObject: JsonObject; var InvoiceNo: Text; var PaymentToken: Text; var CurrencyCode: Code[10]; var GrossAmount: Decimal; var PayerEmail: Text);
    var
        CurrencyCodeTxt: Text;
        GrossAmountTxt: Text;
    begin
        GetJsonPropertyValueByPath(JObject, 'paymentResponse.details.paymentToken', PaymentToken);
        GetJsonPropertyValueByPath(JObject, 'paymentRequest.details.total.label', InvoiceNo);
        GetJsonPropertyValueByPath(JObject, 'paymentRequest.details.total.amount.value', GrossAmountTxt);
        GetJsonPropertyValueByPath(JObject, 'paymentRequest.details.total.amount.currency', CurrencyCodeTxt);
        GetJsonPropertyValueByPath(JObject, 'paymentResponse.payerEmail', PayerEmail);

        IF NOT EVALUATE(GrossAmount, GrossAmountTxt, 9) THEN
            SendTraceTag('00008HX', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, CannotParseAmountTxt, DataClassification::SystemMetadata);
        CurrencyCode := COPYSTR(CurrencyCodeTxt, 1, MAXSTRLEN(CurrencyCode));
    end;

    local procedure ValidateInvoiceDetails(InvoiceNoCode: Code[20]; GrossAmount: Decimal; CurrencyCode: Code[10]);
    var
        SalesInvoiceHeader: Record 112;
        InvoiceCurrencyCode: Code[10];
    begin
        SendTraceTag('00008HY', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, VerifyTransactionDetailsTxt, DataClassification::SystemMetadata);

        IF NOT SalesInvoiceHeader.GET(InvoiceNoCode) THEN BEGIN
            SendTraceTag('00001P8', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, TelemetryUnexpectedInvoiceNumberErr, DataClassification::SystemMetadata);
            LogActivity(StrSubstNo(UnexpectedInvoiceNumberErr, InvoiceNoCode), '');
            ERROR(UnexpectedInvoiceNumberErr, InvoiceNoCode);
        END;

        SalesInvoiceHeader.CALCFIELDS(Closed);
        IF SalesInvoiceHeader.Closed THEN BEGIN
            SendTraceTag('00001P9', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, TelemetryUnexpectedInvoiceClosedErr, DataClassification::SystemMetadata);
            LogActivity(StrSubstNo(UnexpectedInvoiceClosedErr, InvoiceNoCode), '');
            ERROR(UnexpectedInvoiceClosedErr, InvoiceNoCode);
        END;

        InvoiceCurrencyCode := SalesInvoiceHeader."Currency Code";
        IF InvoiceCurrencyCode = '' THEN
            InvoiceCurrencyCode := GetDefaultCurrencyCode();
        IF InvoiceCurrencyCode <> UPPERCASE(CurrencyCode) THEN BEGIN
            SendTraceTag('00001PA', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, UnexpectedCurrencyCodeTelemetryTxt, DataClassification::SystemMetadata);
            LogActivity(StrSubstNo(UnexpectedCurrencyCodeErr, CurrencyCode, InvoiceCurrencyCode), '');
            ERROR(UnexpectedCurrencyCodeErr, CurrencyCode, InvoiceCurrencyCode);
        END;

        IF GrossAmount <= 0 THEN BEGIN
            SendTraceTag('00001PB', MSWalletTelemetryCategoryTok, VERBOSITY::Warning, TelemetryUnexpectedAmountErr, DataClassification::SystemMetadata);
            LogActivity(StrSubstNo(UnexpectedAmountErr, GrossAmount), '');
            ERROR(UnexpectedAmountErr, GrossAmount);
        END;

        SendTraceTag('00008HZ', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, TransactionDetailsVerifiedTxt, DataClassification::SystemMetadata);
    end;

    local procedure SaveChargeResource(JObject: JsonObject): Boolean;
    var
        MSWalletCharge: Record 1086;
        CreateTime: DateTime;
        ChargeAmount: Decimal;
        chargeIdTxt: Text;
        merchantIdTxt: Text;
        createTimeTxt: Text;
        statusTxt: Text;
        currencyTxt: Text;
        descriptionTxt: Text;
        amountTxt: Text;
        referenceIdTxt: Text;
        paymentMethodDescriptionTxt: Text;
    begin
        SendTraceTag('00008I0', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, SaveChargeResourceTxt, DataClassification::SystemMetadata);

        GetJsonPropertyValue(JObject, 'chargeId', chargeIdTxt);
        MSWalletCharge.VALIDATE("Charge ID", chargeIdTxt);

        GetJsonPropertyValue(JObject, 'merchantId', merchantIdTxt);
        MSWalletCharge.VALIDATE("Merchant ID", merchantIdTxt);

        GetJsonPropertyValue(JObject, 'createTime', createTimeTxt);

        IF NOT TryParseDateTime(createTimeTxt, CreateTime) THEN BEGIN
            SendTraceTag('00001PC', MSWalletTelemetryCategoryTok, VERBOSITY::Error, CannotParseCreateTimeTxt, DataClassification::SystemMetadata);
            LogActivity(STRSUBSTNO(UnexpectedCreateTimeErr, createTimeTxt), '');
            EXIT(FALSE);
        END;

        MSWalletCharge.VALIDATE("Create Time", CreateTime);

        GetJsonPropertyValue(JObject, 'status', statusTxt);
        MSWalletCharge.VALIDATE(Status, COPYSTR(statusTxt, 1, MAXSTRLEN(MSWalletCharge.Status)));

        GetJsonPropertyValue(JObject, 'description', descriptionTxt);
        MSWalletCharge.VALIDATE(Description, descriptionTxt);

        GetJsonPropertyValue(JObject, 'currency', currencyTxt);
        MSWalletCharge.VALIDATE(Currency, COPYSTR(currencyTxt, 1, MAXSTRLEN(MSWalletCharge.Currency)));

        GetJsonPropertyValue(JObject, 'amount', amountTxt);
        IF NOT EVALUATE(ChargeAmount, amountTxt, 9) THEN BEGIN
            SendTraceTag('00001PD', MSWalletTelemetryCategoryTok, VERBOSITY::Error, CannotParseAmountTxt, DataClassification::SystemMetadata);
            LogActivity(STRSUBSTNO(UnexpectedAmountErr, amountTxt), '');
            EXIT(FALSE);
        END;

        MSWalletCharge.VALIDATE(Amount, ChargeAmount);

        GetJsonPropertyValue(JObject, 'referenceId', referenceIdTxt);
        MSWalletCharge.VALIDATE("Reference ID", referenceIdTxt);

        GetJsonPropertyValue(JObject, 'paymentMethodDescription', paymentMethodDescriptionTxt);
        MSWalletCharge.VALIDATE("Payment Method Description", paymentMethodDescriptionTxt);

        MSWalletCharge.INSERT(TRUE);
        EXIT(TRUE);
    end;

    local procedure GetMSAccountMode(MSWalletMerchantAccount: Record 1080): Text;
    begin
        IF MSWalletMerchantAccount."Test Mode" OR (STRPOS(LOWERCASE(MSWalletMerchantAccount.GetBaseURL()), 'ppe') <> 0) THEN
            EXIT('TEST');

        EXIT('LIVE');
    end;

    local procedure GetDefaultCurrencyCode(): Code[10];
    var
        GeneralLedgerSetup: Record 98;
        CurrencyCode: Code[10];
    begin
        GeneralLedgerSetup.GET();
        CurrencyCode := GeneralLedgerSetup.GetCurrencyCode(CurrencyCode);
        EXIT(CurrencyCode);
    end;

    local procedure TryParseDateTime(DateTimeText: Text; var ResultDateTime: DateTime): Boolean;
    var
        TypeHelper: Codeunit "Type Helper";
        DateTimeVariant: Variant;
    begin
        DateTimeVariant := 0DT;
        if not TypeHelper.Evaluate(DateTimeVariant, DateTimeText, '', '') then
            exit(false);

        ResultDateTime := DateTimeVariant;
        exit(true);
    end;

    [BusinessEvent(false)]
    local procedure OnAfterPostWalletPayment(var TempPaymentRegistrationBuffer: Record 981 temporary; AmountReceived: Decimal);
    begin
    end;

    [BusinessEvent(false)]
    local procedure OnAfterReceiveWalletOverpayment(var TempPaymentRegistrationBuffer: Record 981 temporary; AmountReceived: Decimal);
    begin
    end;

    [Scope('Internal')]
    procedure CancelInvoiceLastPayment(SalesInvoiceDocumentNo: Code[20]): Boolean;
    var
        InvoiceCustLedgerEntry: Record 21;
        PaymentCustLedgerEntry: Record 21;
        ReversalEntry: Record 179;
        DetailedCustLedgEntry: Record 379;
        CustEntryApplyPostedEntries: Codeunit 226;
    begin
        SENDTRACETAG('00001PE', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, CancellingPaymentTxt, DataClassification::SystemMetadata);
        LogActivity(CancellingPaymentTxt, SalesInvoiceDocumentNo);

        // Find the customer ledger entry related to the invoice
        InvoiceCustLedgerEntry.SETRANGE("Document Type", InvoiceCustLedgerEntry."Document Type"::Invoice);
        InvoiceCustLedgerEntry.SETRANGE("Document No.", SalesInvoiceDocumentNo);
        IF NOT InvoiceCustLedgerEntry.FINDFIRST() THEN
            EXIT(FALSE); // The invoice does not exist

        // Find the customer ledger entry related to the payment of the invoice
        PaymentCustLedgerEntry.Get(InvoiceCustLedgerEntry."Closed by Entry No.");

        IF NOT PaymentCustLedgerEntry.FINDLAST() THEN
            EXIT(FALSE);

        // Get detailed ledger entry for the payment, making sure it's a payment
        DetailedCustLedgEntry.SETRANGE("Document Type", DetailedCustLedgEntry."Document Type"::Payment);
        DetailedCustLedgEntry.SETRANGE("Document No.", PaymentCustLedgerEntry."Document No.");
        DetailedCustLedgEntry.SETRANGE("Cust. Ledger Entry No.", PaymentCustLedgerEntry."Entry No.");
        DetailedCustLedgEntry.SETRANGE(Unapplied, FALSE);
        IF NOT DetailedCustLedgEntry.FINDLAST() THEN
            EXIT(FALSE);

        CustEntryApplyPostedEntries.PostUnApplyCustomerCommit(
          DetailedCustLedgEntry, DetailedCustLedgEntry."Document No.", DetailedCustLedgEntry."Posting Date", true);

        ReversalEntry.SetHideWarningDialogs();
        ReversalEntry.ReverseTransaction(PaymentCustLedgerEntry."Transaction No.");
        Commit();

        SENDTRACETAG('00001PF', MSWalletTelemetryCategoryTok, VERBOSITY::Normal, CancellingPaymentDoneTxt, DataClassification::SystemMetadata);
        LogActivity(CancellingPaymentDoneTxt, SalesInvoiceDocumentNo);
        EXIT(TRUE);
    end;

    local procedure GetJsonPropertyValueByPath(JObject: JsonObject; PropertyPath: Text; var PropertyValue: Text);
    var
        JToken: JsonToken;
        JValue: JsonValue;
    begin
        PropertyValue := '';
        if not JObject.SelectToken(PropertyPath, JToken) then
            exit;
        if not JToken.IsValue() then
            exit;
        JValue := JToken.AsValue();
        if JValue.IsNull() then
            exit;
        PropertyValue := JValue.AsText();
    end;

    local procedure GetJsonPropertyValue(JObject: JsonObject; PropertyKey: Text; var PropertyValue: Text);
    var
        JToken: JsonToken;
        JValue: JsonValue;
    begin
        PropertyValue := '';
        if not JObject.Get(PropertyKey, JToken) then
            exit;
        if not JToken.IsValue() then
            exit;
        JValue := JToken.AsValue();
        if JValue.IsNull() then
            exit;
        PropertyValue := JValue.AsText();
    end;

    local procedure LogActivity(ErrorDescription: Text; ErrorMsg: Text)
    var
        ActivityLog: Record 710;
        MSWalletMerchantAccount: Record 1080;
    begin
        if MSWalletMerchantAccount.FindFirst() then;
        ActivityLog.LogActivity(MSWalletMerchantAccount.RecordId(), ActivityLog.Status::Failed, MSPayContextTxt, ErrorDescription, ErrorMsg);
    end;

    procedure ShowWarningIfCannotMakePayment(MSWalletMerchantAccount: Record 1080)
    var
        ErrorMsg: Text;
    begin
        if not GuiAllowed() then
            exit;
        if not CanAcceptWebhookPayment(MSWalletMerchantAccount, ErrorMsg) then
            Message(StrSubstNo(CannotMakePaymentWarningTxt, ErrorMsg));
    end;

    procedure CanAcceptWebhookPayment(MSWalletMerchantAccount: Record 1080; var ErrorMsg: Text): Boolean;
    var
        WebhookSubscription: Record 2000000199;
        User: Record 2000000120;
        PaymentRegistrationSetup: Record 980;
    begin
        WebhookSubscription.SetRange("Subscription ID", GetWebhookSubscriptionID(MSWalletMerchantAccount."Merchant ID"));
        WebhookSubscription.SetFilter("Created By", GetCreatedByFilterForWebhooks());
        if not WebhookSubscription.FindFirst() then begin
            ErrorMsg := NoWebhookSubscriptionTxt;
            exit(false);
        end;

        if not IsEnabledUser(WebhookSubscription."Run Notification As", User) then begin
            ErrorMsg := SetupUserIsDisabledOrDeletedTxt;
            exit(false);
        end;

        if not PaymentRegistrationSetup.GET(User."User Name") then begin
            ErrorMsg := StrSubstNo(NoPaymentRegistrationSetupErrTxt, User."User Name");
            exit(false);
        end;
        if not PaymentRegistrationSetup.ValidateMandatoryFields(false) then begin
            ErrorMsg := StrSubstNo(PaymentRegistrationSetupFieldErrTxt, WebhookSubscription."Run Notification As");
            exit(false);
        end;
        exit(true);
    end;

    local PROCEDURE IsEnabledUser(UserSID: GUID; var User: Record 2000000120): Boolean;
    BEGIN
        IF User.GET(UserSID) THEN
            EXIT(User.State = User.State::Enabled);

        EXIT(FALSE);
    END;

    [EventSubscriber(ObjectType::Table, 1080, 'OnBeforeDeleteEvent', '', false, false)]
    local procedure OnBeforeDeleteMSWalletAccount(var Rec: Record 1080; RunTrigger: Boolean);
    begin
        CheckMSWalletAccountWithOpenInvoices();
    end;

    [EventSubscriber(ObjectType::Table, 1080, 'OnBeforeValidateEvent', 'Enabled', false, false)]
    local procedure OnBeforeDisableMSWalletAccount(VAR Rec: Record 1080; VAR xRec: Record 1080; CurrFieldNo: Integer)
    begin
        if not Rec.Enabled and xRec.Enabled then
            CheckMSWalletAccountWithOpenInvoices();
    end;

    local procedure CheckMSWalletAccountWithOpenInvoices();
    var
        MSWalletPayment: Record 1085;
        SalesInvoiceHeader: Record 112;
        EnvInfoProxy: Codeunit "Env. Info Proxy";
    begin
        if not GuiAllowed() then
            exit;

        if EnvInfoProxy.IsInvoicing() then
            exit;

        if not MSWalletPayment.FindSet() then
            exit;
        repeat
            IF SalesInvoiceHeader.GET(MSWalletPayment."Invoice No") THEN BEGIN
                SalesInvoiceHeader.CALCFIELDS(Closed);
                IF not SalesInvoiceHeader.Closed THEN begin
                    if Confirm(SetupDeleteOrDisableWithOpenInvoiceQst) then
                        exit;
                    Error('');
                end;
            end;
        until MSWalletPayment.Next() = 0;
    end;
}



