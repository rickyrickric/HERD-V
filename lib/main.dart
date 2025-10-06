import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
// share_plus removed for UI-only testing
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

// Helpers used with compute() must be top-level functions.
// Encode animals list on a background isolate to avoid janking the UI.
String _encodeAnimalsIsolate(List<Map<String, dynamic>> animals) {
  return json.encode(animals);
}

// Run a simple k-means on a background isolate. Expects a map with keys:
// { 'animals': List<Map<String,dynamic>>, 'featureKeys': List<String>, 'k': int, 'maxIter': int }
List<int> _kMeansIsolate(Map<String, dynamic> payload) {
  final animals = (payload['animals'] as List).cast<Map<String, dynamic>>();
  final featureKeys = (payload['featureKeys'] as List).cast<String>();
  final k = payload['k'] as int;
  final maxIter = payload['maxIter'] as int;

  // build feature matrix
  final X = animals.map((a) {
    return featureKeys.map((key) {
      return double.tryParse(a[key]?.toString() ?? '') ?? 0.0;
    }).toList();
  }).toList();

  if (X.isEmpty) return <int>[];
  final rnd = DateTime.now().millisecondsSinceEpoch;
  final rand = Random(rnd);
  final n = X.length;
  final dim = X[0].length;
  final centroids = <List<double>>[];
  final chosen = <int>{};
  while (centroids.length < k) {
    final idx = rand.nextInt(n);
    if (!chosen.contains(idx)) {
      chosen.add(idx);
      centroids.add(List<double>.from(X[idx]));
    }
  }

  List<int> labels = List.filled(n, 0);
  for (var iter = 0; iter < maxIter; iter++) {
    var changed = false;
    // assign
    for (var i = 0; i < n; i++) {
      var best = 0;
      var bestDist = double.infinity;
      for (var j = 0; j < k; j++) {
        var s = 0.0;
        for (var d = 0; d < dim; d++) {
          final diff = X[i][d] - centroids[j][d];
          s += diff * diff;
        }
        if (s < bestDist) {
          bestDist = s;
          best = j;
        }
      }
      if (labels[i] != best) {
        labels[i] = best;
        changed = true;
      }
    }
    if (!changed) break;
    // update centroids
    for (var j = 0; j < k; j++) {
      final members = <List<double>>[];
      for (var i = 0; i < n; i++) {
        if (labels[i] == j) members.add(X[i]);
      }
      if (members.isEmpty) continue;
      final avg = List<double>.filled(dim, 0.0);
      for (var m in members) {
        for (var d = 0; d < dim; d++) {
          avg[d] += m[d];
        }
      }
      for (var d = 0; d < dim; d++) {
        avg[d] /= members.length;
      }
      centroids[j] = avg;
    }
  }
  return labels;
}

void main() {
  runApp(const HerdVApp());
}

// Removed backend HTTP dependency for local UI-first testing

class HerdVApp extends StatefulWidget {
  const HerdVApp({super.key});

  @override
  State<HerdVApp> createState() => _HerdVAppState();
}

class _HerdVAppState extends State<HerdVApp> {
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    _loadTheme(); // load cached animals and sample asset if present
    // don't await here; _loadTheme will call _loadCached indirectly
  }

  Future<void> _loadTheme() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getBool('is_dark_mode') ?? false;
    setState(() => _isDark = v);
  }

  Future<void> _toggleTheme() async {
    final sp = await SharedPreferences.getInstance();
    setState(() => _isDark = !_isDark);
    await sp.setBool('is_dark_mode', _isDark);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      primaryColor: const Color(0xFF2E7D32),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
      scaffoldBackgroundColor: const Color(0xFFF6F8F3),
    );
    final darkTheme = ThemeData.dark().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E7D32),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
    );
    return MaterialApp(
      title: 'HERD-V',
      theme: theme,
      darkTheme: darkTheme,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: HerdDashboard(isDark: _isDark, onToggleTheme: _toggleTheme),
    );
  }
}

class HerdDashboard extends StatefulWidget {
  final bool? isDark;
  final VoidCallback? onToggleTheme;
  const HerdDashboard({super.key, this.isDark, this.onToggleTheme});
  @override
  State<HerdDashboard> createState() => _HerdDashboardState();
}

class _HerdDashboardState extends State<HerdDashboard> {
  List<Map<String, dynamic>> animals = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  Future<void> _loadCached() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString('last_dataset');
    if (s != null) {
      final list = json.decode(s) as List;
      setState(() {
        animals = list.cast<Map<String, dynamic>>();
      });
    }

    // also attempt to load bundled sample.csv asset and merge it if animals empty
    if (animals.isEmpty) {
      try {
        final raw = await rootBundle.loadString('sample.csv');
        final rows = const CsvToListConverter(eol: '\n').convert(raw);
        if (rows.length > 1) {
          final headers = rows.first.map((h) => h.toString()).toList();
          for (var i = 1; i < rows.length; i++) {
            final row = rows[i];
            final m = <String, dynamic>{};
            for (var j = 0; j < headers.length && j < row.length; j++) {
              final key = headers[j];
              final rawVal = row[j]?.toString() ?? '';
              final val = rawVal.trim().replaceAll(RegExp(r"\s*\.\s*"), '.');
              m[key] = val;
            }
            animals.add(m);
          }
          await _cache();
        }
      } catch (e) {
        // asset not present or parse error
      }
    }
  }

  Future<void> _cache() async {
    final sp = await SharedPreferences.getInstance();
    // encode on background isolate to avoid main-thread jank
    final encoded = await compute(_encodeAnimalsIsolate, animals);
    await sp.setString('last_dataset', encoded);
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null) return;
    final bytes =
        result.files.first.bytes ??
        await File(result.files.first.path!).readAsBytes();
    final csv = utf8.decode(bytes);
    final rows = const CsvToListConverter(eol: '\n').convert(csv);
    if (rows.isEmpty) return;
    final headers = rows.first.map((e) => e.toString()).toList();
    final maps = <Map<String, dynamic>>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final m = <String, dynamic>{};
      for (var j = 0; j < headers.length && j < row.length; j++) {
        m[headers[j]] = row[j];
      }
      maps.add(m);
    }
    final required = [
      'ID',
      'Breed',
      'Age',
      'Weight_kg',
      'Milk_Yield',
      'Fertility_Score',
      'Remaining_Months',
    ];
    final missing = required.where((c) => !headers.contains(c)).toList();
    if (missing.isNotEmpty) {
      _showSnackbar('Missing columns: ${missing.join(', ')}');
      return;
    }
    setState(() {
      animals = maps;
    });
    await _cache();
    _showSnackbar('Imported ${maps.length} records');
  }

  Future<void> _manualEntry() async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManualEntryPage()),
    );
    if (!mounted) return;
    if (res != null && res is Map<String, dynamic>) {
      setState(() {
        animals.add(res);
      });
      await _cache();
    }
  }

  Future<void> _runClustering() async {
    if (animals.isEmpty) {
      _showSnackbar('No animal data to cluster');
      return;
    }
    setState(() {
      loading = true;
    });
    try {
      // Run a small local k-means clustering on numeric features so UI can be tested
      final k = 3;
      final featureKeys = [
        'Milk_Yield',
        'Fertility_Score',
        'Weight_kg',
        'Age',
        'Parasite_Load_Index',
        'Fecal_Egg_Count',
        'Ear_Temperature_C',
        'Movement_Score',
        'Remaining_Months',
      ];
      // Run k-means on a background isolate to avoid blocking UI
      final labels = await compute(_kMeansIsolate, {
        'animals': animals,
        'featureKeys': featureKeys,
        'k': k,
        'maxIter': 30,
      });

      // attach labels (lightweight)
      for (var i = 0; i < animals.length; i++) {
        animals[i]['cluster'] = labels.isNotEmpty
            ? labels[i] + 1
            : 1; // make clusters 1-based
      }
      await _cache();

      // build summaries
      final summaries = <Map<String, dynamic>>[];
      for (var cid = 1; cid <= k; cid++) {
        final members = animals.where((a) => a['cluster'] == cid).toList();
        final numericKeys = featureKeys;
        final Map<String, double> means = {};
        for (var key in numericKeys) {
          final vals = members
              .map((m) => double.tryParse(m[key]?.toString() ?? '') ?? 0.0)
              .where((v) => v != 0.0)
              .toList();
          final mean = vals.isEmpty
              ? 0.0
              : vals.reduce((a, b) => a + b) / vals.length;
          means[key] = mean;
        }
        final summ = <String, dynamic>{
          'cluster_id': cid,
          'count': members.length,
        }..addAll(means);
        summ['recommendation'] = _recommendForCluster(summ);
        summaries.add(summ);
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClusterInsightsPage(
            summaries: summaries,
            dendrogramBase64: null,
            animals: animals,
          ),
        ),
      );
    } catch (e) {
      _showSnackbar('Error: $e');
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  // Build feature matrix for k-means (rows: animals, cols: features)
  // ignore: unused_element
  List<List<double>> _buildFeatureMatrix(
    List<Map<String, dynamic>> items,
    List<String> keys,
  ) {
    return items.map((a) {
      return keys.map((k) {
        return double.tryParse(a[k]?.toString() ?? '') ?? 0.0;
      }).toList();
    }).toList();
  }

  // Simple k-means implementation returning zero-based labels
  // ignore: unused_element
  List<int> _kMeans(List<List<double>> X, int k, {int maxIter = 20}) {
    if (X.isEmpty) return [];
    final rnd = DateTime.now().millisecondsSinceEpoch;
    final rand = Random(rnd);
    final n = X.length;
    final dim = X[0].length;
    // init centroids randomly from data
    final centroids = <List<double>>[];
    final chosen = <int>{};
    while (centroids.length < k) {
      final idx = rand.nextInt(n);
      if (!chosen.contains(idx)) {
        chosen.add(idx);
        centroids.add(List<double>.from(X[idx]));
      }
    }

    List<int> labels = List.filled(n, 0);
    for (var iter = 0; iter < maxIter; iter++) {
      var changed = false;
      // assign
      for (var i = 0; i < n; i++) {
        var best = 0;
        var bestDist = double.infinity;
        for (var j = 0; j < k; j++) {
          final d = _squaredDist(X[i], centroids[j]);
          if (d < bestDist) {
            bestDist = d;
            best = j;
          }
        }
        if (labels[i] != best) {
          labels[i] = best;
          changed = true;
        }
      }
      if (!changed) break;
      // update centroids
      for (var j = 0; j < k; j++) {
        final members = <List<double>>[];
        for (var i = 0; i < n; i++) {
          if (labels[i] == j) members.add(X[i]);
        }
        if (members.isEmpty) continue;
        final avg = List<double>.filled(dim, 0.0);
        for (var m in members) {
          for (var d = 0; d < dim; d++) {
            avg[d] += m[d];
          }
        }
        for (var d = 0; d < dim; d++) {
          avg[d] /= members.length;
        }
        centroids[j] = avg;
      }
    }
    return labels;
  }

  double _squaredDist(List<double> a, List<double> b) {
    var s = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      s += d * d;
    }
    return s;
  }

  String _recommendForCluster(Map<String, dynamic> summary) {
    final recs = <String>[];
    final parasite = (summary['Parasite_Load_Index'] ?? 0).toDouble();
    final fecal = (summary['Fecal_Egg_Count'] ?? 0).toDouble();
    final movement = (summary['Movement_Score'] ?? 0).toDouble();
    final milk = (summary['Milk_Yield'] ?? 0).toDouble();
    final temp = (summary['Ear_Temperature_C'] ?? 0).toDouble();
    if (parasite > 3.5 || fecal > 200) {
      recs.add('Consider deworming and fecal testing');
    }
    if (movement < 4) {
      recs.add('Increase pasture rotation and monitor mobility');
    }
    if (milk < 15) {
      recs.add('Review nutrition and milking protocol');
    }
    if (temp > 39.0) {
      recs.add('Inspect for fever/infection; check shelter and water');
    }
    if (recs.isEmpty) {
      recs.add('Normal indicators — continue routine management');
    }
    return recs.join('; ');
  }

  void _showSnackbar(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  double _avg(String key) {
    final nums = animals
        .map((a) => double.tryParse(a[key]?.toString() ?? '') ?? 0.0)
        .where((v) => v != 0.0)
        .toList();
    if (nums.isEmpty) return 0.0;
    return nums.reduce((a, b) => a + b) / nums.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset('assets/icons/cow.svg', height: 28, width: 28),
            const SizedBox(width: 8),
            const Text('HERD-V'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              widget.isDark == true ? Icons.dark_mode : Icons.light_mode,
            ),
            tooltip: 'Toggle theme',
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              setState(() => animals = []);
              final sp = await SharedPreferences.getInstance();
              await sp.remove('last_dataset');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          SvgPicture.asset(
                            'assets/icons/forage.svg',
                            height: 40,
                            width: 40,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Cattle KPIs',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Avg Milk: ${_avg('Milk_Yield').toStringAsFixed(1)} L',
                              ),
                              Text(
                                'Avg Fertility: ${_avg('Fertility_Score').toStringAsFixed(1)} /10',
                              ),
                              Text(
                                'Avg Parasite: ${_avg('Parasite_Load_Index').toStringAsFixed(1)}',
                              ),
                              Text(
                                'Remaining Months: ${_avg('Remaining_Months').toStringAsFixed(0)}',
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _importCsv,
                            icon: SvgPicture.asset(
                              'assets/icons/milk.svg',
                              height: 18,
                              width: 18,
                            ),
                            label: const Text('Import CSV'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _manualEntry,
                            icon: SvgPicture.asset(
                              'assets/icons/hoof.svg',
                              height: 18,
                              width: 18,
                            ),
                            label: const Text('Add Animal'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: animals.isEmpty
                    ? Center(
                        child: Text(
                          'No animals. Import CSV or add manually.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                    : ListView.builder(
                        itemCount: animals.length,
                        itemBuilder: (ctx, i) {
                          final a = animals[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 0,
                            ),
                            child: ListTile(
                              leading: SvgPicture.asset(
                                'assets/icons/cow.svg',
                                height: 36,
                                width: 36,
                              ),
                              title: Text(
                                a['ID']?.toString() ?? 'Unknown',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${a['Breed'] ?? ''} • ${a['Weight_kg'] ?? ''} kg',
                              ),
                              trailing: a['cluster'] != null
                                  ? Chip(
                                      backgroundColor: Colors.brown.shade100,
                                      label: Text('C${a['cluster']}'),
                                    )
                                  : null,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AnimalDetailPage(animal: a),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              ElevatedButton(
                onPressed: loading ? null : _runClustering,
                child: loading
                    ? const CircularProgressIndicator()
                    : const Text('View Cluster Insights'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ManualEntryPage extends StatefulWidget {
  const ManualEntryPage({super.key});

  @override
  State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  final _form = GlobalKey<FormState>();
  final Map<String, dynamic> data = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Animal')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _form,
          child: ListView(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'ID'),
                onSaved: (v) => data['ID'] = v,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Breed'),
                onSaved: (v) => data['Breed'] = v,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Age'),
                keyboardType: TextInputType.number,
                onSaved: (v) => data['Age'] = int.tryParse(v ?? '0'),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Weight_kg'),
                keyboardType: TextInputType.number,
                onSaved: (v) => data['Weight(kg)'] = double.tryParse(v ?? '0'),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Milk_Yield'),
                keyboardType: TextInputType.number,
                onSaved: (v) =>
                    data['Milk Yield(Liters)'] = double.tryParse(v ?? '0'),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Fertility_Score'),
                keyboardType: TextInputType.number,
                onSaved: (v) =>
                    data['Fertility Score'] = double.tryParse(v ?? '0'),
              ),

              SwitchListTile(
                title: const Text('Vaccination Up To Date'),
                value: data['Vaccination_Up_To_Date'] == true,
                onChanged: (v) {
                  setState(() => data['Vaccination_Up_To_Date'] = v);
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      _form.currentState?.save();
                      Navigator.pop(context, data);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClusterInsightsPage extends StatefulWidget {
  final List summaries;
  final String? dendrogramBase64;
  final List<Map<String, dynamic>>? animals;

  const ClusterInsightsPage({
    super.key,
    required this.summaries,
    this.dendrogramBase64,
    this.animals,
  });

  @override
  State<ClusterInsightsPage> createState() => _ClusterInsightsPageState();
}

class _ClusterInsightsPageState extends State<ClusterInsightsPage> {
  @override
  Widget build(BuildContext context) {
    final summaries = widget.summaries;
    final animals = widget.animals;
    final dendrogramBase64 = widget.dendrogramBase64;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cluster Insights'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export recommendations CSV',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (animals == null || animals.isEmpty) {
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('No animal data to export')),
                );
                return;
              }
              final csv = _buildRecommendationsCsv(summaries, animals);
              try {
                // On mobile, write a temporary file and share
                if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                  final tmpDir = await getTemporaryDirectory();
                  final tmpFile = File(
                    '${tmpDir.path}${Platform.pathSeparator}herdv_recommendations.csv',
                  );
                  await tmpFile.writeAsString(csv);
                  // share - messenger was captured above before any awaits
                  // For UI testing we simply save a temporary CSV and notify the user.
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Saved recommendations to ${tmpFile.path}'),
                    ),
                  );
                  return;
                }

                // Desktop or web fallback: save to downloads
                final dir = await getDownloadsDirectory();
                final file = File(
                  '${dir?.path ?? '.'}${Platform.pathSeparator}herdv_recommendations.csv',
                );
                await file.writeAsString(csv);
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Exported to ${file.path}')),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Export failed: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            if (dendrogramBase64 != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Image.memory(base64Decode(dendrogramBase64)),
                ),
              ),
            // Scatter plot (Milk_Yield vs Fertility)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  height: 180,
                  child: ScatterChart(
                    ScatterChartData(
                      scatterSpots: (animals ?? []).map((a) {
                        final x =
                            double.tryParse(
                              a['Fertility_Score']?.toString() ?? '',
                            ) ??
                            0.0;
                        final y =
                            double.tryParse(
                              a['Milk_Yield']?.toString() ?? '',
                            ) ??
                            0.0;
                        return ScatterSpot(x, y);
                      }).toList(),
                      minX: 0,
                      maxX: 10,
                      minY: 0,
                      maxY: (animals != null && animals.isNotEmpty)
                          ? (animals
                                    .map(
                                      (a) =>
                                          double.tryParse(
                                            a['Milk_Yield']?.toString() ?? '0',
                                          ) ??
                                          0,
                                    )
                                    .reduce((a, b) => a > b ? a : b) +
                                10)
                          : 50,
                      gridData: FlGridData(show: true),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (v, meta) =>
                                Text(v.toInt().toString()),
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: true),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Bar chart for mean Milk_Yield per cluster
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  height: 160,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= summaries.length) {
                                return const SizedBox.shrink();
                              }
                              return Text('C${summaries[idx]['cluster_id']}');
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: true),
                        ),
                      ),
                      barGroups: List.generate(summaries.length, (i) {
                        final s = summaries[i] as Map<String, dynamic>;
                        final meanMilk = (s['Milk_Yield'] ?? 0).toDouble();
                        return BarChartGroupData(
                          x: i,
                          barsSpace: 4,
                          barRods: [
                            BarChartRodData(
                              toY: meanMilk,
                              color: Colors.green.shade700,
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: summaries.length,
                itemBuilder: (ctx, i) {
                  final s = summaries[i] as Map<String, dynamic>;
                  final meanMilk = (s['Milk_Yield'] ?? 0).toDouble();
                  final count = s['count'] ?? 0;
                  return Card(
                    child: ListTile(
                      title: Text(
                        'Cluster ${s['cluster_id']} • $count animals',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Avg Milk: ${meanMilk.toStringAsFixed(1)}'),
                          Text('Recommendation: ${s['recommendation'] ?? ''}'),
                        ],
                      ),
                      onTap: () {},
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _buildRecommendationsCsv(
  List summaries,
  List<Map<String, dynamic>> animals,
) {
  // Build CSV with ID, cluster, recommendation
  final rows = <List<String>>[];
  rows.add(['ID', 'Cluster', 'Recommendation']);
  // Map cluster_id to recommendation from summaries
  final recByCluster = <String, String>{};
  for (var s in summaries) {
    final cid = s['cluster_id'].toString();
    recByCluster[cid] = s['recommendation']?.toString() ?? '';
  }
  for (var a in animals) {
    final id = a['ID']?.toString() ?? '';
    final c = a['cluster']?.toString() ?? '';
    final rec = recByCluster[c] ?? '';
    rows.add([id, c, rec]);
  }
  return const ListToCsvConverter().convert(rows);
}

class AnimalDetailPage extends StatelessWidget {
  final Map<String, dynamic> animal;
  const AnimalDetailPage({super.key, required this.animal});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(animal['ID']?.toString() ?? 'Animal')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Breed: ${animal['Breed'] ?? ''}'),
                    Text('Age: ${animal['Age'] ?? ''}'),
                    Text('Weight: ${animal['Weight_kg'] ?? ''} kg'),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    for (var k in animal.keys)
                      if (k != 'ID') Text('$k: ${animal[k]}'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
