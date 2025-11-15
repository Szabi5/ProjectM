// lib/services/notification_service.dart

// --- FIX 1: ADDED THE MAIN PACKAGE IMPORT ---
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// --- FIX 2: Corrected the timezone imports ---
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io' show Platform; // Import for platform checks

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // --- 1. Initialize Timezones ---
    // --- FIX 3: Use the correct aliases ---
    tz_data.initializeTimezoneData(tz_data.latestAll); // Was 'latestall'

    // --- 2. Setup Android/iOS Settings ---
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher' // This uses your app's default icon
    );
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);

    // --- 3. Request Permission (Android 13+ & iOS) ---
    if (Platform.isAndroid) {
      await _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.requestPermission(); // Use requestPermission()
    } else if (Platform.isIOS) {
       await _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  // --- 4. The Scheduling Function ---
  Future<void> scheduleMonthlyReminder() async {
    await _notifications.cancel(0); 

    final tz.Location local = tz.local;
    final tz.TZDateTime now = tz.TZDateTime.now(local);

    tz.TZDateTime scheduledDate = tz.TZDateTime(local, now.year, now.month, 28, 10); 
    if (scheduledDate.isBefore(now)) {
      scheduledDate = tz.TZDateTime(local, now.year, now.month + 1, 28, 10); 
    }

    // --- 5. Notification Details (All enums are now found) ---
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'monthly_snapshot_reminder', 
        'Snapshot Reminders',      
        channelDescription: 'Monthly reminder to save financial snapshot.',
        importance: Importance.medium, // <-- This is now valid
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    // --- 6. Schedule the Repeating Notification ---
    await _notifications.zonedSchedule(
      0, 
      'Financial Snapshot Time! 📈',
      'Time to update your balances and save your monthly history.',
      scheduledDate,
      details,
      uiLocalNotificationDateInterpretation: 
          UILocalNotificationDateInterpretation.absoluteTime, 
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime, 
    );
    
    print("Notification Service: Monthly reminder scheduled for the 28th at 10:00.");
  }
}