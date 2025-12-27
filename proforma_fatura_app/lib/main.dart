import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'constants/app_constants.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/products_screen.dart';
import 'screens/invoices_screen.dart';
import 'screens/add_customer_screen.dart';
import 'screens/product_form_screen.dart';
import 'screens/invoice_form_screen.dart';
import 'screens/company_info_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/auth_wrapper.dart';
import 'providers/hybrid_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error handlers for better crash diagnostics (no zones to avoid zone mismatch)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: \'${details.exception}\'');
    if (details.stack != null) {
      debugPrint(details.stack.toString());
    }
  };
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PlatformDispatcher error: $error');
    debugPrint(stack.toString());
    return true; // handled
  };

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Replace default error widget to avoid hard crashes and log details
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('ErrorWidget caught: \'${details.exceptionAsString()}\'');
    if (details.stack != null) {
      debugPrint(details.stack.toString());
    }
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.error_outline, color: Colors.red, size: 48),
              SizedBox(height: 12),
              Text('Beklenmeyen bir hata oluştu. Günlükler (logs) kaydedildi.'),
            ],
          ),
        ),
      ),
    );
  };

  runApp(const ProformaFaturaApp());
}

class ProformaFaturaApp extends StatelessWidget {
  const ProformaFaturaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Hybrid Provider - SQLite (offline) + Firebase (online)
        ChangeNotifierProvider(
          create: (_) {
            final provider = HybridProvider();
            provider.initialize();
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          // Tüm uygulama genelinde Roboto (assets/fonts) kullan
          fontFamily: 'Roboto',
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppConstants.primaryColor,
            brightness: Brightness.light,
            primary: AppConstants.primaryColor,
            secondary: AppConstants.secondaryColor,
            tertiary: AppConstants.accentColor,
            surface: AppConstants.surfaceColor,
            error: AppConstants.errorColor,
            onPrimary: AppConstants.textOnPrimary,
            onSurface: AppConstants.textOnSurface,
            outline: AppConstants.borderColor,
          ),
          primaryColor: AppConstants.primaryColor,
          scaffoldBackgroundColor: AppConstants.backgroundColor,
          dividerColor: AppConstants.dividerColor,

          appBarTheme: AppBarTheme(
            backgroundColor: AppConstants.primaryColor,
            foregroundColor: AppConstants.textOnPrimary,
            elevation: 0,
            centerTitle: true,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppConstants.textOnPrimary,
              fontFamily: 'Roboto',
            ),
            iconTheme: const IconThemeData(color: AppConstants.textOnPrimary),
          ),

          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: AppConstants.textOnPrimary,
              disabledBackgroundColor: AppConstants.textTertiary,
              disabledForegroundColor: AppConstants.textOnPrimary,
              minimumSize: const Size(
                double.infinity,
                AppConstants.buttonHeight,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              ),
              elevation: 0,
              shadowColor: AppConstants.primaryColor.withOpacity(0.3),
            ),
          ),

          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppConstants.primaryColor,
              side: const BorderSide(color: AppConstants.primaryColor),
              minimumSize: const Size(
                double.infinity,
                AppConstants.buttonHeight,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              ),
            ),
          ),

          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: AppConstants.primaryColor,
              minimumSize: const Size(0, AppConstants.buttonHeight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              ),
            ),
          ),

          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppConstants.surfaceColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              borderSide: const BorderSide(color: AppConstants.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              borderSide: const BorderSide(color: AppConstants.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              borderSide: const BorderSide(
                color: AppConstants.primaryColor,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              borderSide: const BorderSide(color: AppConstants.errorColor),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              borderSide: const BorderSide(
                color: AppConstants.errorColor,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppConstants.paddingMedium,
              vertical: AppConstants.paddingMedium,
            ),
            hintStyle: const TextStyle(color: AppConstants.textSecondary),
            labelStyle: const TextStyle(color: AppConstants.textSecondary),
            floatingLabelStyle: const TextStyle(
              color: AppConstants.primaryColor,
            ),
          ),

          cardTheme: CardThemeData(
            elevation: AppConstants.cardElevation,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            ),
            color: AppConstants.surfaceColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: AppConstants.textTertiary.withOpacity(0.1),
          ),

          chipTheme: ChipThemeData(
            backgroundColor: AppConstants.surfaceVariant,
            selectedColor: AppConstants.primaryLight,
            disabledColor: AppConstants.borderLight,
            labelStyle: const TextStyle(color: AppConstants.textPrimary),
            secondaryLabelStyle: const TextStyle(
              color: AppConstants.textOnPrimary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            ),
          ),

          dialogTheme: DialogThemeData(
            backgroundColor: AppConstants.surfaceColor,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            ),
            titleTextStyle: AppConstants.subheadingStyle,
            contentTextStyle: AppConstants.bodyStyle,
          ),

          bottomSheetTheme: BottomSheetThemeData(
            backgroundColor: AppConstants.surfaceColor,
            surfaceTintColor: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppConstants.borderRadius),
              ),
            ),
          ),

          snackBarTheme: SnackBarThemeData(
            backgroundColor: AppConstants.textPrimary,
            contentTextStyle: const TextStyle(
              color: AppConstants.textOnPrimary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
        locale: const Locale('tr', 'TR'),
        home: const AuthWrapper(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const HomeScreen(),
          '/customers': (context) => const CustomersScreen(),
          '/products': (context) => const ProductsScreen(),
          '/invoices': (context) => const InvoicesScreen(),
          '/add-customer': (context) => const AddCustomerScreen(),
          '/product-form': (context) => const ProductFormScreen(),
          '/invoice-form': (context) => const InvoiceFormScreen(),
          '/company-info': (context) => const CompanyInfoScreen(),
          '/profile': (context) => const ProfileScreen(),
        },
      ),
    );
  }
}
