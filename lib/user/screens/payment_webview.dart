import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentWebView extends StatefulWidget {
  final String checkoutUrl;
  final String orderId;
  final String paymentMethod;

  const PaymentWebView({
    super.key,
    required this.checkoutUrl,
    required this.orderId,
    required this.paymentMethod,
  });

  @override
  State<PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<PaymentWebView> {
  InAppWebViewController? webViewController;

  bool _isLoading = true;

  // Prevent multiple success handlers from running
  // if PayMongo redirects several times.
  bool _isProcessingSuccess = false;

  Future<void> _handlePaymentSuccess() async {
    // Prevent duplicate processing
    if (_isProcessingSuccess) return;

    setState(() {
      _isProcessingSuccess = true;
    });

    try {
      final orderDocRef = FirebaseFirestore.instance
          .collection("orders")
          .doc(widget.orderId);

      final orderSnapshot = await orderDocRef.get();

      if (!orderSnapshot.exists) {
        throw Exception("Order record missing.");
      }

      final orderData = orderSnapshot.data();

      if (orderData == null) {
        throw Exception("Order data is missing.");
      }

      // Check if this order has already been marked as paid.
      final bool alreadyPaid = orderData["isPaid"] == true;

      if (!alreadyPaid) {
        // IMPORTANT:
        // This file DOES NOT deduct product stock.
        //
        // Stock deduction is handled ONLY by checkout_page.dart
        // after this PaymentWebView returns "SUCCESS".
        //
        // This prevents the stock from being deducted twice.

        await orderDocRef.update({
          "isPaid": true,
          "prepareToShip": true,
          "status": "Pending",
          "orderStatus": "Pending",
          "paymentMethod":
          widget.paymentMethod == "gcash" ? "GCash" : "Maya",
        });

        debugPrint(
          "Online Payment Success: Order marked as PAID. "
              "Stock will be deducted by CheckoutPage.",
        );
      } else {
        debugPrint(
          "Online Payment Success: Order was already marked as PAID. "
              "Skipping duplicate update.",
        );
      }

      if (mounted) {
        Navigator.pop(context, "SUCCESS");
      }
    } catch (e) {
      debugPrint("ERROR PROCESSING ONLINE PAYMENT: $e");

      if (mounted) {
        Navigator.pop(context, "FAILED");
      }
    }
  }

  void _checkUrlForStatus(String urlString) {
    debugPrint("Checking WebView URL: $urlString");

    final lowerUrl = urlString.toLowerCase();

    // Successful PayMongo payment
    if (lowerUrl.contains("payment-success") ||
        lowerUrl.contains("success.paymongo.com") ||
        lowerUrl.contains("success")) {
      _handlePaymentSuccess();
      return;
    }

    // Cancelled / failed payment
    if (lowerUrl.contains("payment-cancel") ||
        lowerUrl.contains("cancel.paymongo.com") ||
        lowerUrl.contains("failed")) {
      if (mounted && !_isProcessingSuccess) {
        Navigator.pop(context, "FAILED");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("PayMongo Secure Payment"),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (!_isProcessingSuccess) {
              Navigator.pop(context, "CANCELLED");
            }
          },
        ),
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(widget.checkoutUrl),
            ),

            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
              supportZoom: false,
              clearCache: true,
            ),

            onWebViewCreated: (controller) {
              webViewController = controller;
            },

            onLoadStart: (controller, url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                });
              }

              if (url != null) {
                _checkUrlForStatus(url.toString());
              }
            },

            onLoadStop: (controller, url) async {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }

              if (url != null) {
                _checkUrlForStatus(url.toString());
              }
            },

            onUpdateVisitedHistory: (
                controller,
                url,
                isReload,
                ) {
              if (url != null) {
                _checkUrlForStatus(url.toString());
              }
            },

            shouldOverrideUrlLoading: (
                controller,
                navigationAction,
                ) async {
              final uri = navigationAction.request.url;

              if (uri != null) {
                _checkUrlForStatus(uri.toString());
              }

              return NavigationActionPolicy.ALLOW;
            },

            onLoadError: (
                controller,
                url,
                code,
                message,
                ) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }

              debugPrint(
                "PayMongo WebView Load Error: "
                    "$code - $message",
              );
            },

            onLoadHttpError: (
                controller,
                url,
                statusCode,
                description,
                ) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }

              debugPrint(
                "PayMongo WebView HTTP Error: "
                    "$statusCode - $description",
              );
            },
          ),

          // Loading indicator
          if (_isLoading || _isProcessingSuccess)
            Container(
              color: Colors.black.withValues(alpha: 0.05),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.green,
                ),
              ),
            ),
        ],
      ),
    );
  }
}