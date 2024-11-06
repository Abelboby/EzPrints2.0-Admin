import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:async';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EzPrints Admin Panel',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _controller.forward();

    // Navigate to main screen after animation
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => 
            const MyHomePage(title: 'EzPrints Admin Panel'),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _animation,
              child: const Icon(
                Icons.print_rounded,
                size: 100,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: _animation,
              child: const Text(
                'EzPrints Admin Panel',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 48),
            ScaleTransition(
              scale: _animation,
              child: const CircularProgressIndicator(
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String selectedFilter = 'All';
  bool isAutomationEnabled = false;
  StreamSubscription? _printJobsSubscription;
  bool isGridView = false;
  String searchQuery = '';
  Set<String> _processedJobs = {};  // Add this to track processed jobs
  Process? _pythonProcess;
  bool isPythonScriptRunning = false;

  @override
  void initState() {
    super.initState();
    // Start listening to print jobs
    listenToPrintJobs();
  }

  void listenToPrintJobs() {
    _printJobsSubscription?.cancel(); // Cancel any existing subscription
    _printJobsSubscription = getPrintJobs().listen((jobs) async {
      // Only process jobs if automation is enabled
      if (!isAutomationEnabled) return;  // Add this check
      
      for (var job in jobs) {
        // Check if job is paid AND hasn't been processed yet
        if (job.status == 'paid' && !_processedJobs.contains(job.id)) {
          _processedJobs.add(job.id); // Mark as processed immediately
          
          try {
            // Download and print file
            final file = await downloadFile(job.ipfsUrl, job.fileName);
            await printFile(file, job);
            
            // Update status in Firebase
            await FirebaseFirestore.instance
                .collection('printJobs')
                .doc(job.id)
                .update({'status': 'printed'});
                
          } catch (e) {
            print('Error processing print job: $e');
            await FirebaseFirestore.instance
                .collection('printJobs')
                .doc(job.id)
                .update({
                  'status': 'error',
                  'error': e.toString()
                });
            // Remove from processed jobs if there was an error
            _processedJobs.remove(job.id);
          }
        }
      }
    });
  }

  Future<File> downloadFile(String url, String fileName) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw 'Failed to download file: ${response.statusCode}';
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  Future<void> printFile(File file, PrintJob job) async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) => file.readAsBytes(),
        name: job.fileName,
      );
    } catch (e) {
      print('Printing error: $e');
      throw e;
    }
  }

  Future<void> _showPdfPreview(PrintJob job) async {
    try {
      showDialog(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(job.fileName),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (job.status == 'paid')
                  IconButton(
                    icon: const Icon(Icons.print),
                    onPressed: () async {
                      final file = await downloadFile(job.ipfsUrl, job.fileName);
                      await printFile(file, job);
                    },
                  ),
              ],
            ),
            body: SfPdfViewer.network(
              job.ipfsUrl,
              onDocumentLoadFailed: (details) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error loading PDF: ${details.error}')),
                );
              },
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading PDF: $e')),
      );
    }
  }

  Future<void> _showPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Admin Password'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (passwordController.text == 'admin123') {
                setState(() {
                  isAutomationEnabled = true;
                });
                _startAutomation();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Automation Enabled')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect Password')),
                );
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _startPythonScript() async {
    try {
      // First ensure any existing instances are stopped
      _stopPythonScript();
      
      _pythonProcess = await Process.start('python', ['assets/print_dialog_handler.py']);
      
      setState(() {
        isPythonScriptRunning = true;
      });

      // Listen for script output
      _pythonProcess!.stdout.transform(utf8.decoder).listen((data) {
        print('Python script output: $data');
      });

      _pythonProcess!.stderr.transform(utf8.decoder).listen((data) {
        print('Python script error: $data');
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Print Dialog Handler Started')),
      );

    } catch (e) {
      print('Error starting Python script: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting print dialog handler: $e')),
      );
    }
  }

  void _stopPythonScript() {
    try {
      if (_pythonProcess != null) {
        // Kill the process and all its children
        Process.runSync('taskkill', ['/F', '/T', '/PID', '${_pythonProcess!.pid}']);
        _pythonProcess = null;
      }

      // Additional safety: Kill any remaining python processes running our script
      Process.runSync('taskkill', ['/F', '/IM', 'python.exe', '/FI', 'WINDOWTITLE eq print_dialog_handler.py']);
      
    } catch (e) {
      print('Error stopping Python script: $e');
    } finally {
      setState(() {
        isPythonScriptRunning = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Print Dialog Handler Stopped')),
      );
    }
  }

  void _toggleAutomation(bool value) {
    setState(() {
      isAutomationEnabled = value;
    });
    if (value) {
      _showPasswordDialog();
    } else {
      _printJobsSubscription?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Automation Disabled')),
      );
    }
  }

  void _startAutomation() {
    if (isAutomationEnabled) {
      _processedJobs.clear();
      listenToPrintJobs();
    } else {
      _printJobsSubscription?.cancel();
    }
  }

  @override
  void dispose() {
    _stopPythonScript();
    _printJobsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Automation Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Print Jobs Dashboard',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Manage and monitor all print jobs in one place',
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Automation Toggle
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Auto Print: ',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Switch(
                              value: isAutomationEnabled,
                              onChanged: _toggleAutomation,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Print Dialog Handler Toggle
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Print Dialog Handler: ',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Switch(
                              value: isPythonScriptRunning,
                              onChanged: (bool value) {
                                if (value) {
                                  _startPythonScript();
                                } else {
                                  _stopPythonScript();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Existing view toggle buttons
                    IconButton(
                      icon: const Icon(Icons.grid_view),
                      onPressed: () => setState(() => isGridView = true),
                      color: isGridView ? Colors.blue : Colors.grey,
                    ),
                    IconButton(
                      icon: const Icon(Icons.list),
                      onPressed: () => setState(() => isGridView = false),
                      color: !isGridView ? Colors.blue : Colors.grey,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Search Bar
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by file name or ID...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase();
                });
              },
            ),
            const SizedBox(height: 20),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var filter in [
                    'All',
                    'Pending',
                    'Awaiting_Payment',
                    'Paid',
                    'Printing',
                    'Printed',
                    'Completed',
                    'Cancelled',
                    'Error'
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text(filter),
                        selected: selectedFilter == filter,
                        onSelected: (bool selected) {
                          setState(() {
                            selectedFilter = filter;
                          });
                        },
                        backgroundColor: Colors.white,
                        selectedColor: Colors.blue[100],
                        checkmarkColor: Colors.blue,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Print Jobs List
            Expanded(
              child: StreamBuilder<List<PrintJob>>(
                stream: getPrintJobs(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 60, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(
                            'Error: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  if (!snapshot.hasData) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Loading print jobs...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  var jobs = snapshot.data!;
                  
                  // Filter jobs based on selected status
                  if (selectedFilter != 'All') {
                    jobs = jobs.where((job) => 
                      job.status.toLowerCase() == selectedFilter.toLowerCase()
                    ).toList();
                  }

                  // Apply search filter
                  if (searchQuery.isNotEmpty) {
                    jobs = jobs.where((job) =>
                      job.fileName.toLowerCase().contains(searchQuery) ||
                      job.id.toLowerCase().contains(searchQuery)
                    ).toList();
                  }

                  return isGridView
                      ? GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 2.0,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            mainAxisExtent: 160,
                          ),
                          itemCount: jobs.length,
                          itemBuilder: (context, index) {
                            final job = jobs[index];
                            return Card(
                              child: InkWell(
                                onTap: () => _showPdfPreview(job),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              job.fileName,
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.more_vert),
                                            onPressed: () => _showJobDetails(job),
                                          ),
                                          _buildStatusChip(job.status),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'ID: ${job.id}',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const Spacer(),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          _buildInfoItem(Icons.copy, '${job.copies}'),
                                          _buildInfoItem(Icons.palette, job.colorMode),
                                          _buildInfoItem(Icons.description, job.paperSize),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Submitted: ${_formatDate(job.timestamp)}',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          itemCount: jobs.length,
                          itemBuilder: (context, index) {
                            final job = jobs[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: InkWell(
                                onTap: () => _showPdfPreview(job),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  job.fileName,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  'ID: ${job.id}',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.more_vert),
                                            onPressed: () => _showJobDetails(job),
                                          ),
                                          _buildStatusChip(job.status),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          _buildInfoItem(Icons.copy, '${job.copies} copies'),
                                          const SizedBox(width: 24),
                                          _buildInfoItem(Icons.palette, job.colorMode),
                                          const SizedBox(width: 24),
                                          _buildInfoItem(Icons.description, job.paperSize),
                                          const SizedBox(width: 24),
                                          _buildInfoItem(Icons.attach_money, '₹${job.paymentAmount.toStringAsFixed(2)}'),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Submitted: ${_formatDate(job.timestamp)}',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    Color chipColor;
    Color textColor = Colors.white;
    switch (status.toLowerCase()) {
      case 'paid':
        chipColor = Colors.blue;
        break;
      case 'printed':
        chipColor = Colors.green;
        break;
      case 'error':
        chipColor = Colors.red;
        break;
      case 'awaiting_payment':
        chipColor = Colors.blue[50]!;
        textColor = Colors.blue;
        break;
      case 'cancelled':
        chipColor = Colors.red[50]!;
        textColor = Colors.red;
        break;
      default:
        chipColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _formatDate(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      return '${date.month}/${date.day}/${date.year}, ${date.hour}:${date.minute}:${date.second} ${date.hour >= 12 ? 'PM' : 'AM'}';
    } catch (e) {
      return timestamp;
    }
  }

  void _showJobDetails(PrintJob job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(job.fileName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Status History'),
              subtitle: const Text('Track status changes'),
              onTap: () {
                // Implement status history tracking
              },
            ),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Reprint'),
              subtitle: const Text('Print this job again'),
              onTap: () {
                Navigator.pop(context); // Close job details dialog
                _confirmReprint(job);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete Job'),
              subtitle: const Text('Remove from system'),
              onTap: () {
                _confirmDeleteJob(job);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmReprint(PrintJob job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Reprint'),
        content: Text('Are you sure you want to reprint "${job.fileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close confirmation dialog
              _showReprintPasswordDialog(job);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reprint'),
          ),
        ],
      ),
    );
  }

  void _showReprintPasswordDialog(PrintJob job) {
    final TextEditingController passwordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Admin Password'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passwordController.text == 'admin123') {
                try {
                  await FirebaseFirestore.instance
                      .collection('printJobs')
                      .doc(job.id)
                      .update({'status': 'paid'});
                      
                  Navigator.pop(context); // Close password dialog
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Print job status updated to paid')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating print job: $e')),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect Password')),
                );
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteJob(PrintJob job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete "${job.fileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('printJobs')
                    .doc(job.id)
                    .delete();
                    
                Navigator.pop(context); // Close confirmation dialog
                Navigator.pop(context); // Close job details dialog
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Print job deleted successfully')),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error deleting print job: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class PrintJob {
  final String colorMode;
  final int copies;
  final bool doubleSided;
  final String fileName;
  final int fileSize;
  final String fileType;
  final String ipfsUrl;
  final String orientation;
  final String paperSize;
  final String status;
  final String timestamp;
  final String id;
  final double paymentAmount;

  PrintJob.fromMap(Map<String, dynamic> map, this.id)
      : colorMode = map['colorMode'] ?? '',
        copies = map['copies'] ?? 0,
        doubleSided = map['doubleSided'] ?? false,
        fileName = map['fileName'] ?? '',
        fileSize = map['fileSize'] ?? 0,
        fileType = map['fileType'] ?? '',
        ipfsUrl = map['ipfsUrl'] ?? '',
        orientation = map['orientation'] ?? '',
        paperSize = map['paperSize'] ?? '',
        status = map['status'] ?? '',
        timestamp = map['timestamp'] ?? '',
        paymentAmount = (map['paymentAmount'] ?? 0).toDouble();
}

// Function to fetch print jobs
Stream<List<PrintJob>> getPrintJobs() {
  return FirebaseFirestore.instance
      .collection('printJobs')
      .snapshots()
      .map((snapshot) {
        var jobs = snapshot.docs.map((doc) {
          return PrintJob.fromMap(doc.data(), doc.id);
        }).toList();
        
        // Sort jobs by timestamp in descending order
        jobs.sort((a, b) => DateTime.parse(b.timestamp).compareTo(DateTime.parse(a.timestamp)));
        return jobs;
      });
}