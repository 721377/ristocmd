import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'Homepage.dart';
// import '../pages/order_page.dart'; // You'll need to create this
// import '../pages/profile_page.dart'; // You'll need to create this
// import '../widgets/bottom_navbar.dart'; // Your custom bottom bar

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isConnected = true;

  // List of pages to display based on the selected tab
  final List<Widget> _pages = [
    HomePage(), // We don't need category here
    PlaceholderPage(title: "Orders"), // Replace with your orders page
    PlaceholderPage(title: "Menu"), // Replace with your menu page
    // ProfilePage(), // Replace with your profile page
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> checkInternetConnection(BuildContext context) async {
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      setState(() {
        _isConnected = false;
      });
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("No Internet Connection"),
          content: Text("Please check your internet settings and try again."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
    } else {
      setState(() {
        _isConnected = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    checkInternetConnection(context);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  Future<void> _handleRefresh() async {
    await Future.delayed(Duration(seconds: 2));
    checkInternetConnection(context);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        // bottomNavigationBar: BottomNavBar(
        //   currentIndex: _currentIndex,
        //   onTap: _onTabTapped,
        // ),
      ),
    );
  }
}

// Placeholder for other pages - replace with your actual pages
class PlaceholderPage extends StatelessWidget {
  final String title;

  const PlaceholderPage({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Center(
        child: Text(title),
      ),
    );
  }
}