// lib/main.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

/// A simple data class for Courses
class Course {
  String uid;
  String? courseId; // optional
  String name;
  String semester;
  double grade;
  double credits;

  Course({
    required this.uid,
    this.courseId,
    required this.name,
    required this.semester,
    required this.grade,
    required this.credits,
  });

  // For loading from JSON
  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      uid: json['uid'] ?? "",
      courseId: json['course_id'],
      name: json['name'] ?? "",
      semester: json['semester'] ?? "",
      grade: (json['grade'] ?? 0).toDouble(),
      credits: (json['credits'] ?? 0).toDouble(),
    );
  }

  // For saving to JSON
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'course_id': courseId,
      'name': name,
      'semester': semester,
      'grade': grade,
      'credits': credits,
    };
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Using Material 3 for a modern design
    return MaterialApp(
      title: 'GPA & Pass/Fail Calculator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const MainHomePage(),
    );
  }
}

class MainHomePage extends StatefulWidget {
  const MainHomePage({super.key});

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

///
/// This widget hosts the two main tabs:
/// 1) "Saved Grades"
/// 2) "Optimal Binary Pass"
/// and shows a tutorial popup when launched.
///
class _MainHomePageState extends State<MainHomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // We store all "past" courses in a list
  List<Course> savedCourses = [];

  // For the "current semester" courses
  List<Course> currSemCourses = [];

  // A local JSON file name
  final String dataFileName = "courses_data.json";

  // For the tutorial popup on launch
  bool _tutorialShown = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedCourses();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTutorial();
    });
  }

  /// Show the tutorial popup
  void _showTutorial() {
    if (_tutorialShown) return; // so we don't show it multiple times
    _tutorialShown = true;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Tutorial"),
          content: const Text(
            "Welcome to the Offline GPA & Pass/Fail Calculator!\n\n"
            "1. 'Saved Grades' Tab: Add courses (Course ID optional) and directly edit them in the table.\n"
            "   The table is sortable by any column, and changes are saved automatically.\n\n"
            "2. 'Optimal Binary Pass' Tab: Enter current-semester courses. You can also directly edit these cells. Then compute the optimal pass/fail combination.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Got It!"),
            ),
          ],
        );
      },
    );
  }

  /// A private getter for the local File reference
  Future<File> get _localFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$dataFileName');
  }

  /// Loads courses from local JSON
  Future<void> _loadSavedCourses() async {
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> data = json.decode(contents);
        final loaded = data.map((d) => Course.fromJson(d)).toList();
        setState(() {
          savedCourses = loaded;
        });
      }
    } catch (e) {
      debugPrint("Could not load data: $e");
    }
  }

  /// Saves the `savedCourses` list to local JSON
  Future<void> _saveCourses() async {
    try {
      final file = await _localFile;
      final data = savedCourses.map((c) => c.toJson()).toList();
      await file.writeAsString(json.encode(data));
    } catch (e) {
      debugPrint("Could not save data: $e");
    }
  }

  // Weighted average of a list of Course
  double calculateAverage(List<Course> courses) {
    if (courses.isEmpty) return 0.0;
    double totalWeighted = 0;
    double totalCredits = 0;
    for (final c in courses) {
      totalWeighted += c.grade * c.credits;
      totalCredits += c.credits;
    }
    return (totalCredits == 0) ? 0.0 : totalWeighted / totalCredits;
  }

  // How much the average would rise if a single course had grade=100
  double calculateImprovement(Course course, List<Course> allCourses) {
    if (allCourses.isEmpty) return 0.0;
    final currentAvg = calculateAverage(allCourses);
    double totalWeighted = 0;
    double totalCredits = 0;

    for (final c in allCourses) {
      totalWeighted += c.grade * c.credits;
      totalCredits += c.credits;
    }
    // Hypothetical: if course had 100
    final hypotheticalWeighted = totalWeighted
        - (course.grade * course.credits)
        + (100.0 * course.credits);
    final hypotheticalAvg = (totalCredits == 0) ? 0 : hypotheticalWeighted / totalCredits;
    return hypotheticalAvg - currentAvg;
  }

  /// Among the newSem courses with grade >= 55, pick up to passLimit to convert
  /// to pass (excluded from numeric average) to maximize final average.
  /// Returns (bestAverage, subsetOfCoursesPassed)
  ///
  (double, List<Course>) findOptimalPassFail(
    List<Course> pastCourses,
    List<Course> newSemCourses,
    int passLimit,
  ) {
    final allCourses = [...pastCourses, ...newSemCourses];
    if (passLimit <= 0 || newSemCourses.isEmpty) {
      return (calculateAverage(allCourses), []);
    }

    final passEligible = newSemCourses.where((c) => c.grade >= 55).toList();
    if (passEligible.isEmpty) {
      return (calculateAverage(allCourses), []);
    }

    double bestAvg = calculateAverage(allCourses);
    List<Course> bestSubset = [];

    int maxToPass = (passLimit < passEligible.length) ? passLimit : passEligible.length;

    // Simple subset generator for small sets
    Iterable<List<Course>> generateCombinations(List<Course> list, int r) sync* {
      if (r == 0) {
        yield [];
      } else {
        for (int i = 0; i < list.length; i++) {
          final first = list[i];
          final remaining = list.sublist(i + 1);
          for (final sub in generateCombinations(remaining, r - 1)) {
            yield [first, ...sub];
          }
        }
      }
    }

    for (int subsetSize = 0; subsetSize <= maxToPass; subsetSize++) {
      for (final subset in generateCombinations(passEligible, subsetSize)) {
        final subsetIds = subset.map((e) => e.uid).toSet();
        final numericOnly = allCourses.where((c) => !subsetIds.contains(c.uid)).toList();
        final currAvg = calculateAverage(numericOnly);
        if (currAvg > bestAvg) {
          bestAvg = currAvg;
          bestSubset = subset;
        }
      }
    }

    return (bestAvg, bestSubset);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GPA & Pass/Fail Calculator"),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showTutorial,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.school), text: "Saved Grades"),
            Tab(icon: Icon(Icons.check_circle), text: "Optimal Binary Pass"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1) SavedGradesTab
          SavedGradesTab(
            savedCourses: savedCourses,
            onUpdateCourses: (updatedList) async {
              setState(() {
                savedCourses = updatedList;
              });
              await _saveCourses(); // automatically save
            },
            calculateAvg: calculateAverage,
            calculateImprovement: calculateImprovement,
          ),
          // 2) OptimalBinaryPassTab
          OptimalBinaryPassTab(
            savedCourses: savedCourses,
            currSemCourses: currSemCourses,
            onCurrSemCoursesUpdated: (updated) {
              setState(() {
                currSemCourses = updated;
              });
            },
            calculateAvg: calculateAverage,
            findOptimalPassFail: findOptimalPassFail,
          ),
        ],
      ),
    );
  }
}

//
// 1) "Saved Grades" Tab
//
class SavedGradesTab extends StatefulWidget {
  final List<Course> savedCourses;
  final Future<void> Function(List<Course>) onUpdateCourses;
  final double Function(List<Course>) calculateAvg;
  final double Function(Course, List<Course>) calculateImprovement;

  const SavedGradesTab({
    super.key,
    required this.savedCourses,
    required this.onUpdateCourses,
    required this.calculateAvg,
    required this.calculateImprovement,
  });

  @override
  State<SavedGradesTab> createState() => _SavedGradesTabState();
}

class _SavedGradesTabState extends State<SavedGradesTab> {
  final _courseIdCtrl = TextEditingController(); // optional
  final _nameCtrl = TextEditingController();
  final _semesterCtrl = TextEditingController();
  final _gradeCtrl = TextEditingController(text: "80");
  final _creditsCtrl = TextEditingController(text: "3.0");

  // Sorting
  int _sortColumnIndex = 1; // start by sorting by Name by default
  bool _sortAscending = true;
  late List<Course> _tableData;

  @override
  void initState() {
    super.initState();
    _tableData = List.from(widget.savedCourses);
    _sortData();
  }

  @override
  void didUpdateWidget(covariant SavedGradesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If parent updates the savedCourses, we update local
    _tableData = List.from(widget.savedCourses);
    _sortData();
  }

  void _sortData() {
    // We'll define column indices as follows:
    // 0 => courseId, 1 => name, 2 => semester, 3 => grade,
    // 4 => credits, 5 => weight, 6 => improvement
    _tableData.sort((a, b) {
      double? aValDouble, bValDouble; 
      String? aValStr, bValStr;
      switch (_sortColumnIndex) {
        case 0: // courseId (String, might be null)
          aValStr = a.courseId ?? "";
          bValStr = b.courseId ?? "";
          final cmp0 = aValStr.compareTo(bValStr);
          return _sortAscending ? cmp0 : -cmp0;

        case 1: // name (String)
          final cmp1 = a.name.compareTo(b.name);
          return _sortAscending ? cmp1 : -cmp1;

        case 2: // semester (String)
          final cmp2 = a.semester.compareTo(b.semester);
          return _sortAscending ? cmp2 : -cmp2;

        case 3: // grade (double)
          aValDouble = a.grade;
          bValDouble = b.grade;
          final cmp3 = aValDouble.compareTo(bValDouble);
          return _sortAscending ? cmp3 : -cmp3;

        case 4: // credits (double)
          aValDouble = a.credits;
          bValDouble = b.credits;
          final cmp4 = aValDouble.compareTo(bValDouble);
          return _sortAscending ? cmp4 : -cmp4;

        case 5: // weight = grade*credits
          final aWeight = a.grade * a.credits;
          final bWeight = b.grade * b.credits;
          final cmp5 = aWeight.compareTo(bWeight);
          return _sortAscending ? cmp5 : -cmp5;

        case 6: // improvement
          final aImpro = widget.calculateImprovement(a, _tableData);
          final bImpro = widget.calculateImprovement(b, _tableData);
          final cmp6 = aImpro.compareTo(bImpro);
          return _sortAscending ? cmp6 : -cmp6;

        default:
          // if for some reason it's not recognized, just fallback to name
          final fallback = a.name.compareTo(b.name);
          return _sortAscending ? fallback : -fallback;
      }
    });
  }

  Future<void> _updateCell(Course course, String fieldLabel) async {
    final ctrl = TextEditingController();
    switch (fieldLabel) {
      case "Course ID":
        ctrl.text = course.courseId ?? "";
        break;
      case "Name":
        ctrl.text = course.name;
        break;
      case "Semester":
        ctrl.text = course.semester;
        break;
      case "Grade":
        ctrl.text = course.grade.toString();
        break;
      case "Credits":
        ctrl.text = course.credits.toString();
        break;
      default:
        return; // Weight & Improvement are read-only
    }

    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text("Edit $fieldLabel"),
          content: TextField(
            controller: ctrl,
            keyboardType: (fieldLabel == "Grade" || fieldLabel == "Credits")
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
    if (updated == null) return; // canceled

    setState(() {
      switch (fieldLabel) {
        case "Course ID":
          course.courseId = updated.isEmpty ? null : updated;
          break;
        case "Name":
          course.name = updated;
          break;
        case "Semester":
          course.semester = updated;
          break;
        case "Grade":
          final parsed = double.tryParse(updated) ?? 0.0;
          course.grade = parsed;
          break;
        case "Credits":
          final parsed = double.tryParse(updated) ?? 1.0;
          course.credits = parsed;
          break;
      }
    });
    // save automatically
    await widget.onUpdateCourses(_tableData);
  }

  Future<void> _addNewCourse() async {
    final cID = _courseIdCtrl.text.trim().isEmpty ? null : _courseIdCtrl.text.trim();
    final cName = _nameCtrl.text.trim();
    final cSem = _semesterCtrl.text.trim();
    if (cName.isEmpty || cSem.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter at least Name and Semester.")));
      return;
    }
    final gVal = double.tryParse(_gradeCtrl.text.trim()) ?? 0.0;
    final crVal = double.tryParse(_creditsCtrl.text.trim()) ?? 1.0;

    final newCourse = Course(
      uid: UniqueKey().toString(),
      courseId: cID,
      name: cName,
      semester: cSem,
      grade: gVal,
      credits: crVal,
    );
    _tableData.add(newCourse);
    await widget.onUpdateCourses(_tableData);

    // Clear fields
    _courseIdCtrl.clear();
    _nameCtrl.clear();
    _semesterCtrl.clear();
    _gradeCtrl.text = "80";
    _creditsCtrl.text = "3.0";

    setState(() {
      _sortData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentAvg = widget.calculateAvg(_tableData);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            "Saved Grades (Sortable by Any Column & Direct Edit)",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              columns: [
                // 0 => Course ID
                DataColumn(
                  label: const Text("Course ID"),
                  onSort: (colIndex, ascending) {
                    setState(() {
                      _sortColumnIndex = colIndex;
                      _sortAscending = ascending;
                      _sortData();
                    });
                  },
                ),
                // 1 => Name
                DataColumn(
                  label: const Text("Name"),
                  onSort: (colIndex, ascending) {
                    setState(() {
                      _sortColumnIndex = colIndex;
                      _sortAscending = ascending;
                      _sortData();
                    });
                  },
                ),
                // 2 => Semester
                DataColumn(
                  label: const Text("Semester"),
                  onSort: (colIndex, ascending) {
                    setState(() {
                      _sortColumnIndex = colIndex;
                      _sortAscending = ascending;
                      _sortData();
                    });
                  },
                ),
                // 3 => Grade
                DataColumn(
                  label: const Text("Grade"),
                  numeric: true,
                  onSort: (colIndex, ascending) {
                    setState(() {
                      _sortColumnIndex = colIndex;
                      _sortAscending = ascending;
                      _sortData();
                    });
                  },
                ),
                // 4 => Credits
                DataColumn(
                  label: const Text("Credits"),
                  numeric: true,
                  onSort: (colIndex, ascending) {
                    setState(() {
                      _sortColumnIndex = colIndex;
                      _sortAscending = ascending;
                      _sortData();
                    });
                  },
                ),
                // 5 => Weight
                DataColumn(
                  label: const Text("Weight"),
                  numeric: true,
                  onSort: (colIndex, ascending) {
                    setState(() {
                      _sortColumnIndex = colIndex;
                      _sortAscending = ascending;
                      _sortData();
                    });
                  },
                ),
                // 6 => Improvement
                DataColumn(
                  label: const Text("Improvement"),
                  numeric: true,
                  onSort: (colIndex, ascending) {
                    setState(() {
                      _sortColumnIndex = colIndex;
                      _sortAscending = ascending;
                      _sortData();
                    });
                  },
                ),
              ],
              rows: _tableData.map((course) {
                final weight = course.grade * course.credits;
                final improvement = widget.calculateImprovement(course, _tableData);
                return DataRow(
                  cells: [
                    DataCell(
                      Text(course.courseId ?? ""),
                      onTap: () => _updateCell(course, "Course ID"),
                    ),
                    DataCell(
                      Text(course.name),
                      onTap: () => _updateCell(course, "Name"),
                    ),
                    DataCell(
                      Text(course.semester),
                      onTap: () => _updateCell(course, "Semester"),
                    ),
                    DataCell(
                      Text("${course.grade}"),
                      onTap: () => _updateCell(course, "Grade"),
                    ),
                    DataCell(
                      Text("${course.credits}"),
                      onTap: () => _updateCell(course, "Credits"),
                    ),
                    DataCell(Text(weight.toStringAsFixed(2))),
                    DataCell(Text(improvement.toStringAsFixed(2))),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Current Overall Average: ${currentAvg.toStringAsFixed(2)}",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Divider(height: 1, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text("Add a New Past Course (Course ID optional)",
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _courseIdCtrl,
            decoration: const InputDecoration(labelText: "Course ID (optional)"),
          ),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: "Name"),
          ),
          TextField(
            controller: _semesterCtrl,
            decoration: const InputDecoration(labelText: "Semester"),
          ),
          TextField(
            controller: _gradeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: "Grade (0-100)"),
          ),
          TextField(
            controller: _creditsCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: "Credits"),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _addNewCourse,
            child: const Text("Add Course"),
          ),
        ],
      ),
    );
  }
}

//
// 2) "Optimal Binary Pass" Tab
//
class OptimalBinaryPassTab extends StatefulWidget {
  final List<Course> savedCourses;
  final List<Course> currSemCourses;
  final void Function(List<Course>) onCurrSemCoursesUpdated;
  final double Function(List<Course>) calculateAvg;
  final (double, List<Course>) Function(List<Course>, List<Course>, int) findOptimalPassFail;

  const OptimalBinaryPassTab({
    super.key,
    required this.savedCourses,
    required this.currSemCourses,
    required this.onCurrSemCoursesUpdated,
    required this.calculateAvg,
    required this.findOptimalPassFail,
  });

  @override
  State<OptimalBinaryPassTab> createState() => _OptimalBinaryPassTabState();
}

enum PastGradeChoice {
  useSaved,
  enterOverall,
  enterSemesters,
}

class _OptimalBinaryPassTabState extends State<OptimalBinaryPassTab> {
  PastGradeChoice _choice = PastGradeChoice.useSaved;

  final _overallAvgCtrl = TextEditingController(text: "80.0");
  final _overallCreditsCtrl = TextEditingController(text: "30.0");

  int _numSemesters = 1;
  List<_SemesterInfo> semList = [];

  int _passLimit = 0;

  final _currNameCtrl = TextEditingController();
  final _currGradeCtrl = TextEditingController(text: "75.0");
  final _currCreditsCtrl = TextEditingController(text: "3.0");

  late List<Course> _currentSemTable;
  String _resultText = "";

  @override
  void initState() {
    super.initState();
    _currentSemTable = List.from(widget.currSemCourses);
    _buildSemesterInputs();
  }

  @override
  void didUpdateWidget(covariant OptimalBinaryPassTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _currentSemTable = List.from(widget.currSemCourses);
  }

  void _buildSemesterInputs() {
    semList = List.generate(_numSemesters, (index) {
      return _SemesterInfo(
        gradeCtrl: TextEditingController(text: "80.0"),
        creditsCtrl: TextEditingController(text: "15.0"),
      );
    });
  }

  void _saveCurrentSemChanges() {
    widget.onCurrSemCoursesUpdated(_currentSemTable);
  }

  Future<void> _updateCurrSemCell(Course course, String fieldLabel) async {
    final ctrl = TextEditingController();
    switch (fieldLabel) {
      case "Name":
        ctrl.text = course.name;
        break;
      case "Grade":
        ctrl.text = course.grade.toString();
        break;
      case "Credits":
        ctrl.text = course.credits.toString();
        break;
      default:
        return;
    }

    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text("Edit $fieldLabel"),
          content: TextField(
            controller: ctrl,
            keyboardType: (fieldLabel == "Grade" || fieldLabel == "Credits")
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
    if (updated == null) return;
    setState(() {
      double? parsed;
      switch (fieldLabel) {
        case "Name":
          course.name = updated;
          break;
        case "Grade":
          parsed = double.tryParse(updated) ?? course.grade;
          course.grade = parsed;
          break;
        case "Credits":
          parsed = double.tryParse(updated) ?? course.credits;
          course.credits = parsed;
          break;
      }
    });
    _saveCurrentSemChanges();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text("Optimal Binary Pass", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text("Step 1: Provide Your Past Grades", style: Theme.of(context).textTheme.titleMedium),

          Row(
            children: [
              Expanded(
                child: RadioListTile<PastGradeChoice>(
                  title: const Text("Use My Saved Grades"),
                  value: PastGradeChoice.useSaved,
                  groupValue: _choice,
                  onChanged: (val) => setState(() => _choice = val!),
                ),
              ),
              Expanded(
                child: RadioListTile<PastGradeChoice>(
                  title: const Text("Enter Overall Past Average & Credits"),
                  value: PastGradeChoice.enterOverall,
                  groupValue: _choice,
                  onChanged: (val) => setState(() => _choice = val!),
                ),
              ),
            ],
          ),
          RadioListTile<PastGradeChoice>(
            title: const Text("Enter by Past Semesters"),
            value: PastGradeChoice.enterSemesters,
            groupValue: _choice,
            onChanged: (val) => setState(() => _choice = val!),
          ),

          if (_choice == PastGradeChoice.enterOverall) _buildOverallInput(),
          if (_choice == PastGradeChoice.enterSemesters) _buildSemesterWidget(),

          const Divider(height: 30),
          Text("Step 2: Current Semester & Pass Limit", style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              const Text("Number of Binary Passes Allowed:"),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: _passLimit.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  label: "$_passLimit",
                  onChanged: (val) {
                    setState(() {
                      _passLimit = val.round();
                    });
                  },
                ),
              ),
              Text("$_passLimit"),
            ],
          ),

          const SizedBox(height: 16),
          Text("Current Semester Courses (Direct Edit)",
              style: Theme.of(context).textTheme.titleSmall),

          const SizedBox(height: 8),
          TextField(
            controller: _currNameCtrl,
            decoration: const InputDecoration(labelText: "Course Name"),
          ),
          TextField(
            controller: _currGradeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: "Grade (0-100)"),
          ),
          TextField(
            controller: _currCreditsCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: "Credits"),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _addCurrentSemCourse,
            child: const Text("Add This Semester Course"),
          ),

          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text("Name")),
                DataColumn(label: Text("Grade"), numeric: true),
                DataColumn(label: Text("Credits"), numeric: true),
              ],
              rows: _currentSemTable.map((c) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(c.name),
                      onTap: () => _updateCurrSemCell(c, "Name"),
                    ),
                    DataCell(
                      Text("${c.grade}"),
                      onTap: () => _updateCurrSemCell(c, "Grade"),
                    ),
                    DataCell(
                      Text("${c.credits}"),
                      onTap: () => _updateCurrSemCell(c, "Credits"),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _computeOptimalPassFail,
            child: const Text("Compute Optimal Pass/Fail"),
          ),

          const SizedBox(height: 16),
          Text(_resultText, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildOverallInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _overallAvgCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: "Overall Past Average (0-100)"),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _overallCreditsCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: "Total Past Credits"),
        ),
      ],
    );
  }

  Widget _buildSemesterWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text("How many past semesters?"),
            const SizedBox(width: 16),
            DropdownButton<int>(
              value: _numSemesters,
              items: List.generate(20, (index) => index + 1).map((val) {
                return DropdownMenuItem<int>(
                  value: val,
                  child: Text("$val"),
                );
              }).toList(),
              onChanged: (newVal) {
                setState(() {
                  _numSemesters = newVal!;
                  _buildSemesterInputs();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < semList.length; i++)
          Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Semester ${i + 1}"),
                  const SizedBox(height: 8),
                  TextField(
                    controller: semList[i].gradeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Average (0-100)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: semList[i].creditsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Credits"),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _addCurrentSemCourse() {
    if (_currNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter a course name.")));
      return;
    }
    final gval = double.tryParse(_currGradeCtrl.text.trim()) ?? 0.0;
    final cval = double.tryParse(_currCreditsCtrl.text.trim()) ?? 1.0;
    final newCourse = Course(
      uid: UniqueKey().toString(),
      courseId: null,
      name: _currNameCtrl.text.trim(),
      semester: "Current",
      grade: gval,
      credits: cval,
    );
    setState(() {
      _currentSemTable.add(newCourse);
    });
    _saveCurrentSemChanges();

    _currNameCtrl.clear();
    _currGradeCtrl.text = "75.0";
    _currCreditsCtrl.text = "3.0";
  }

  void _computeOptimalPassFail() {
    List<Course> pastCoursesForCalc = [];
    switch (_choice) {
      case PastGradeChoice.useSaved:
        pastCoursesForCalc = List.from(widget.savedCourses);
        break;
      case PastGradeChoice.enterOverall:
        final avgVal = double.tryParse(_overallAvgCtrl.text.trim()) ?? 0.0;
        final credVal = double.tryParse(_overallCreditsCtrl.text.trim()) ?? 0.0;
        if (credVal <= 0) {
          setState(() {
            _resultText = "Total Past Credits must be > 0.";
          });
          return;
        }
        pastCoursesForCalc = [
          Course(
            uid: "aggregated",
            courseId: null,
            name: "Aggregated Past",
            semester: "Aggregated",
            grade: avgVal,
            credits: credVal,
          )
        ];
        break;
      case PastGradeChoice.enterSemesters:
        pastCoursesForCalc = [];
        for (int i = 0; i < semList.length; i++) {
          final gval = double.tryParse(semList[i].gradeCtrl.text.trim()) ?? 0.0;
          final cval = double.tryParse(semList[i].creditsCtrl.text.trim()) ?? 0.0;
          pastCoursesForCalc.add(
            Course(
              uid: "sem$i",
              courseId: null,
              name: "Past Sem ${i + 1}",
              semester: "Sem ${i + 1}",
              grade: gval,
              credits: cval,
            ),
          );
        }
        break;
    }

    final (bestFinalAvg, subsetPassed) =
        widget.findOptimalPassFail(pastCoursesForCalc, _currentSemTable, _passLimit);
    final noPassAvg = widget.calculateAvg([...pastCoursesForCalc, ..._currentSemTable]);

    String buffer = """
<b>Average Before Any Pass/Fail:</b> ${noPassAvg.toStringAsFixed(2)}<br>
<b>Optimized Final Average:</b> ${bestFinalAvg.toStringAsFixed(2)}<br>
""";
    if (subsetPassed.isNotEmpty) {
      buffer += "<b>Courses Converted to Pass:</b><br>";
      for (final c in subsetPassed) {
        buffer += "- ${c.name} (grade=${c.grade})<br>";
      }
    } else {
      buffer += "No courses were converted to Pass.";
    }
    setState(() {
      _resultText = buffer;
    });
  }
}

class _SemesterInfo {
  final TextEditingController gradeCtrl;
  final TextEditingController creditsCtrl;
  _SemesterInfo({
    required this.gradeCtrl,
    required this.creditsCtrl,
  });
}
