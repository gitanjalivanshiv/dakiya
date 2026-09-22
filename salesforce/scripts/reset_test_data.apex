// Restores the org to a known fixture state. Run before each behaviour scenario
// so write actions (confirm received, report not received, record refund) cannot
// leave the next scenario testing against mutated data.
//
// Deletes ALL Dakiya records: this org holds only fixtures at present. Once real
// intake is wired up in Phase 7, narrow this to Notes__c = 'TESTDATA'.
delete [SELECT Id FROM Tracking_Event__c];
delete [SELECT Id FROM Return__c];
delete [SELECT Id FROM Shipment__c];
delete [SELECT Id FROM Purchase_Item__c];
delete [SELECT Id FROM Purchase__c];
delete [SELECT Id FROM Inbound_Message__c];
delete [SELECT Id FROM Notification__c];
delete [SELECT Id FROM Vendor__c];

Vendor__c myntra = new Vendor__c(Name='Myntra', Channel__c='Marketplace',
    Email_Sender_Patterns__c='myntra.in', SMS_Sender_Patterns__c='MYNTRA',
    Return_Window_Days__c=14, Typical_Refund_Days__c=5, Usual_Refund_Mode__c='Original Payment',
    Refund_History_Summary__c='2 returns: 2 full to original payment');
Vendor__c nykaa = new Vendor__c(Name='Nykaa', Channel__c='Marketplace',
    Email_Sender_Patterns__c='nykaa.com', SMS_Sender_Patterns__c='NYKAA', Return_Window_Days__c=7);
Vendor__c insta = new Vendor__c(Name='@soap_studio', Channel__c='Instagram',
    Instagram_Handle__c='@soap_studio', Follow_Up_After_Days__c=5);
insert new List<Vendor__c>{myntra, nykaa, insta};

Purchase__c p1 = new Purchase__c(Vendor__c=myntra.Id, Title__c='Blue kurta set',
    External_Order_Id__c='MN20260915001', Vendor_Order_Key__c='t:mn1', Status__c='Shipped',
    Status_Rank__c=40, Total_Amount__c=2499, Order_Date__c=Date.today().addDays(-6),
    Expected_Delivery__c=Date.today().addDays(1), Source__c='Email',
    Last_Event_At__c=Datetime.now().addDays(-1), Notes__c='TESTDATA');
Purchase__c p2 = new Purchase__c(Vendor__c=nykaa.Id, Title__c='Vitamin C serum + sunscreen',
    External_Order_Id__c='NYK889231', Vendor_Order_Key__c='t:nyk1', Status__c='Delivered (Unconfirmed)',
    Status_Rank__c=60, Total_Amount__c=1899, Order_Date__c=Date.today().addDays(-5),
    Delivered_At__c=Datetime.now().addHours(-20), Return_Window_Ends__c=Date.today().addDays(2),
    Source__c='Email', Last_Event_At__c=Datetime.now().addHours(-20), Notes__c='TESTDATA');
Purchase__c p3 = new Purchase__c(Vendor__c=insta.Id, Title__c='Lavender soap x3',
    Vendor_Order_Key__c='t:insta1', Status__c='Placed', Status_Rank__c=10, Total_Amount__c=650,
    Order_Date__c=Date.today().addDays(-12), Source__c='Chat',
    Last_Event_At__c=Datetime.now().addDays(-12), Notes__c='TESTDATA');
Purchase__c p4 = new Purchase__c(Vendor__c=myntra.Id, Title__c='Red dress',
    External_Order_Id__c='MN20260820044', Vendor_Order_Key__c='t:mn2', Status__c='Return in Progress',
    Status_Rank__c=80, Total_Amount__c=3200, Order_Date__c=Date.today().addDays(-30),
    Source__c='Email', Last_Event_At__c=Datetime.now().addDays(-4), Notes__c='TESTDATA');
insert new List<Purchase__c>{p1, p2, p3, p4};

insert new List<Purchase_Item__c>{
    new Purchase_Item__c(Name='Blue kurta set', Purchase__c=p1.Id, Quantity__c=1, Price__c=2499, Status__c='Active'),
    new Purchase_Item__c(Name='Vitamin C serum', Purchase__c=p2.Id, Quantity__c=1, Price__c=1299, Status__c='Active'),
    new Purchase_Item__c(Name='Sunscreen SPF 50', Purchase__c=p2.Id, Quantity__c=1, Price__c=600, Status__c='Active')
};
insert new List<Shipment__c>{
    new Shipment__c(Purchase__c=p1.Id, Courier__c='Delhivery', AWB__c='DL7741209835',
        Status__c='Shipped', Tracking_URL__c='https://www.delhivery.com/track/package/DL7741209835'),
    new Shipment__c(Purchase__c=p2.Id, Courier__c='Ekart', AWB__c='EK5520117744',
        Status__c='Delivered', Delivered_At__c=Datetime.now().addHours(-20), Confirmation__c='Pending')
};
insert new Return__c(Purchase__c=p4.Id, Type__c='Return', Reason__c='TESTDATA wrong size',
    Status__c='Refund Initiated', Requested_On__c=Date.today().addDays(-10),
    Refund_Initiated_On__c=Date.today().addDays(-6), Refund_Check_Due__c=Date.today().addDays(-1),
    Expected_Refund_Amount__c=3200);
insert new List<Tracking_Event__c>{
    new Tracking_Event__c(Purchase__c=p1.Id, Event_Type__c='shipped', Event_At__c=Datetime.now().addDays(-3),
        Summary__c='Shipped via Delhivery', Applied_By__c='Rule'),
    new Tracking_Event__c(Purchase__c=p2.Id, Event_Type__c='delivered', Event_At__c=Datetime.now().addHours(-20),
        Summary__c='Delivered', Applied_By__c='Rule')
};
System.debug('RESET ok');
