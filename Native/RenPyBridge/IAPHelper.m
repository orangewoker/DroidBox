@import UIKit;
@import StoreKit;

/// Ren'Py resolves this class dynamically through Pyobjus. DroidBox does not sell
/// Android in-app products, but keeping the interface prevents games that merely
/// probe the store API from failing during initialization.
@interface IAPHelper : NSObject <SKProductsRequestDelegate, SKPaymentTransactionObserver>
@property NSArray<NSString *> *productIdentifiers;
@property NSMutableDictionary<NSString *, SKProduct *> *products;
@property NSMutableSet<NSString *> *purchased;
@property NSMutableSet<NSString *> *deferred;
@property int initialized_queue;
@property int validated;
@property int finished;
@property NSString *dialogTitle;
- (void)initQueue;
- (BOOL)canMakePayments;
- (void)validateProductIdentifiersInBackground;
- (void)validateProductIdentifiers;
- (void)beginPurchase:(NSString *)identifier;
- (void)restorePurchases;
- (void)showDialog;
- (void)hideDialog;
- (BOOL)hasPurchased:(NSString *)identifier;
- (BOOL)hasPurchasedConsumable:(NSString *)identifier;
- (BOOL)isDeferred:(NSString *)identifier;
- (NSString *)formatPrice:(NSString *)identifier;
- (void)requestReview;
@end

@implementation IAPHelper
static UIAlertController *DroidBoxStoreAlert;

- (id)init {
    self = [super init];
    if (!self) return nil;
    self.products = [NSMutableDictionary dictionary];
    self.purchased = [NSMutableSet set];
    self.deferred = [NSMutableSet set];
    self.finished = 1;
    self.dialogTitle = @"Contacting App Store";
    return self;
}
- (void)initQueue {
    if (self.initialized_queue) return;
    [SKPaymentQueue.defaultQueue addTransactionObserver:self];
    self.initialized_queue = 1;
}
- (BOOL)canMakePayments {
    [self initQueue];
    return SKPaymentQueue.canMakePayments;
}
- (void)validateProductIdentifiers {
    if (self.validated) { self.finished = 1; return; }
    self.finished = 0;
    [self showDialog];
    SKProductsRequest *request = [[SKProductsRequest alloc]
        initWithProductIdentifiers:[NSSet setWithArray:self.productIdentifiers ?: @[]]];
    request.delegate = self;
    [request start];
}
- (void)validateProductIdentifiersInBackground { [self validateProductIdentifiers]; }
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    for (SKProduct *product in response.products) self.products[product.productIdentifier] = product;
    [self hideDialog];
    self.validated = 1;
    self.finished = 1;
}
- (void)beginPurchase:(NSString *)identifier {
    [self initQueue];
    SKProduct *product = self.products[identifier];
    if (!product) return;
    self.finished = 0;
    [self showDialog];
    [SKPaymentQueue.defaultQueue addPayment:[SKPayment paymentWithProduct:product]];
}
- (void)restorePurchases {
    [self initQueue];
    self.finished = 0;
    [self showDialog];
    [SKPaymentQueue.defaultQueue restoreCompletedTransactions];
}
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
    for (SKPaymentTransaction *transaction in transactions) {
        NSString *identifier = transaction.payment.productIdentifier;
        switch (transaction.transactionState) {
        case SKPaymentTransactionStatePurchased:
        case SKPaymentTransactionStateRestored:
            [self.purchased addObject:identifier];
            [self.deferred removeObject:identifier];
            [queue finishTransaction:transaction];
            [self hideDialog];
            self.finished = 1;
            break;
        case SKPaymentTransactionStateFailed:
            [queue finishTransaction:transaction];
            [self hideDialog];
            self.finished = 1;
            break;
        case SKPaymentTransactionStateDeferred:
            [self.deferred addObject:identifier];
            [self hideDialog];
            self.finished = 1;
            break;
        case SKPaymentTransactionStatePurchasing:
            break;
        @unknown default:
            self.finished = 1;
            break;
        }
    }
}
- (void)paymentQueue:(SKPaymentQueue *)queue
    restoreCompletedTransactionsFailedWithError:(NSError *)error {
    [self hideDialog];
    self.finished = 1;
}
- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    [self hideDialog];
    self.finished = 1;
}
- (void)showDialog {
    if (DroidBoxStoreAlert) return;
    DroidBoxStoreAlert = [UIAlertController
        alertControllerWithTitle:self.dialogTitle
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    indicator.center = CGPointMake(
        DroidBoxStoreAlert.view.bounds.size.width / 2,
        DroidBoxStoreAlert.view.bounds.size.height - 50
    );
    [indicator startAnimating];
    [DroidBoxStoreAlert.view addSubview:indicator];

    UIWindow *window = nil;
    for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (candidate.isKeyWindow) { window = candidate; break; }
    }
    window = window ?: UIApplication.sharedApplication.windows.firstObject;
    [window.rootViewController presentViewController:DroidBoxStoreAlert
                                             animated:YES
                                           completion:nil];
}
- (void)hideDialog {
    [DroidBoxStoreAlert dismissViewControllerAnimated:YES completion:nil];
    DroidBoxStoreAlert = nil;
}
- (BOOL)hasPurchased:(NSString *)identifier { return [self.purchased containsObject:identifier]; }
- (BOOL)hasPurchasedConsumable:(NSString *)identifier {
    BOOL result = [self.purchased containsObject:identifier];
    [self.purchased removeObject:identifier];
    return result;
}
- (BOOL)isDeferred:(NSString *)identifier { return [self.deferred containsObject:identifier]; }
- (NSString *)formatPrice:(NSString *)identifier {
    SKProduct *product = self.products[identifier];
    if (!product) return nil;
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.numberStyle = NSNumberFormatterCurrencyStyle;
    formatter.locale = product.priceLocale;
    return [formatter stringFromNumber:product.price];
}
- (void)requestReview {
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    if ([scene isKindOfClass:UIWindowScene.class]) {
        [SKStoreReviewController requestReviewInScene:scene];
    }
}
@end
