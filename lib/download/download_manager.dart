import '../ext/uri_ext.dart';
import 'download_isolate_pool.dart';
import 'download_status.dart';
import 'download_task.dart';

/// Manages the lifecycle and orchestration of download isolates.
/// This class is responsible for initializing, tracking, and disposing
/// download isolates, as well as delegating download tasks.
class DownloadManager {
  /// The pool that manages all download isolates.
  late DownloadIsolatePool _isolatePool;

  /// Constructs a [DownloadIsolateManager] with an optional maximum number of concurrent downloads.
  DownloadManager([int maxConcurrentDownloads = MAX_ISOLATE_POOL_SIZE]) {
    _isolatePool = DownloadIsolatePool(poolSize: maxConcurrentDownloads);
  }

  /// Provides a stream of [DownloadTask] updates for listeners.
  Stream<DownloadTask> get stream => _isolatePool.streamController.stream;

  /// Provides a stream of task count updates.
  /// Listeners will be notified whenever the number of tasks changes.
  Stream<int> get taskCountStream => _isolatePool.taskCountStream;

  /// Returns all download tasks currently managed.
  List<DownloadTask> get allTasks => _isolatePool.taskList;

  /// Returns all active (downloading) tasks.
  List<DownloadTask> get activeTasks => _isolatePool.taskList
      .where((task) => task.status == DownloadStatus.DOWNLOADING)
      .toList();

  /// Returns the configured pool size.
  int get poolSize => _isolatePool.poolSize;

  /// Returns the current number of isolates in the pool.
  int get isolateSize => _isolatePool.isolateList.length;

  /// Returns the current total number of tasks (including all statuses).
  int get taskCount => allTasks.length;

  /// Returns the current number of active (downloading) tasks.
  int get activeTaskCount => activeTasks.length;

  /// Adds a new [DownloadTask] to the pool.
  Future<DownloadTask> addTask(DownloadTask task) {
    return _isolatePool.addTask(task);
  }

  /// Executes a [DownloadTask], scheduling it for download.
  Future<DownloadTask> executeTask(DownloadTask task) {
    return _isolatePool.executeTask(task);
  }

  /// Triggers the isolate pool to schedule and run tasks.
  Future<void> roundIsolate() {
    return _isolatePool.roundIsolate();
  }

  /// Pauses a task by its [taskId].
  void pauseTaskById(String taskId) {
    _isolatePool.notifyIsolate(taskId, DownloadStatus.PAUSED);
  }

  /// Resumes a task by its [taskId].
  void resumeTaskById(String taskId) {
    _isolatePool.notifyIsolate(taskId, DownloadStatus.DOWNLOADING);
  }

  /// Cancels a task by its [taskId].
  void cancelTaskById(String taskId) {
    _isolatePool.notifyIsolate(taskId, DownloadStatus.CANCELLED);
  }

  /// Pauses a task by its URL.
  void pauseTaskByUrl(String url) {
    String? taskId =
        activeTasks.where((task) => task.url == url).firstOrNull?.id;
    if (taskId != null) {
      _isolatePool.notifyIsolate(taskId, DownloadStatus.PAUSED);
    }
  }

  /// Resumes a task by its URL.
  void resumeTaskByUrl(String url) {
    String? taskId =
        activeTasks.where((task) => task.url == url).firstOrNull?.id;
    if (taskId != null) {
      _isolatePool.notifyIsolate(taskId, DownloadStatus.DOWNLOADING);
    }
  }

  /// Cancels a task by its URL and removes it from the task list.
  void cancelTaskByUrl(String url) {
    String? taskId =
        activeTasks.where((task) => task.url == url).firstOrNull?.id;
    if (taskId != null) {
      _isolatePool.notifyIsolate(taskId, DownloadStatus.CANCELLED);
    }
    bool removed = allTasks.any((task) => task.url == url);
    allTasks.removeWhere((task) => task.url == url);
    if (removed) {
      _isolatePool.notifyTaskCountChange();
    }
  }

  /// Cancels all tasks matching the given [matchUrl] and removes them from the task list.
  /// This is useful for canceling all segments of a video that share the same cache key.
  void cancelTasksByMatchUrl(String matchUrl) {
    List<DownloadTask> matchingTasks = allTasks
        .where((task) => task.matchUrl == matchUrl)
        .toList();
    for (var task in matchingTasks) {
      _isolatePool.notifyIsolate(task.id, DownloadStatus.CANCELLED);
    }
    bool removed = matchingTasks.isNotEmpty;
    allTasks.removeWhere((task) => task.matchUrl == matchUrl);
    if (removed) {
      _isolatePool.notifyTaskCountChange();
    }
  }

  /// Cancels all tasks with the given [hlsKey] and removes them from the task list.
  /// This is useful for canceling all segments of an HLS video.
  void cancelTasksByHlsKey(String hlsKey) {
    List<DownloadTask> matchingTasks = allTasks
        .where((task) => task.hlsKey == hlsKey)
        .toList();
    for (var task in matchingTasks) {
      _isolatePool.notifyIsolate(task.id, DownloadStatus.CANCELLED);
    }
    bool removed = matchingTasks.isNotEmpty;
    allTasks.removeWhere((task) => task.hlsKey == hlsKey);
    if (removed) {
      _isolatePool.notifyTaskCountChange();
    }
  }

  /// Cancels all tasks related to a video URL.
  /// This will cancel tasks by URL, matchUrl, and hlsKey to ensure all related downloads are stopped.
  /// [url]: The video URL to cancel all related tasks for.
  /// [headers]: Optional headers to match tasks (for custom cache ID matching).
  void cancelVideoTasks(String url, {Map<String, Object>? headers}) {
    // Cancel by exact URL
    cancelTaskByUrl(url);
    
    // Cancel by matchUrl (for MP4 segments)
    try {
      final uri = Uri.parse(url);
      DownloadTask sampleTask = DownloadTask(uri: uri, headers: headers);
      cancelTasksByMatchUrl(sampleTask.matchUrl);
    } catch (e) {
      // Ignore parsing errors
    }
    
    // Cancel by hlsKey (for HLS segments)
    try {
      final uri = Uri.parse(url);
      String hlsKey = uri.generateMd5;
      cancelTasksByHlsKey(hlsKey);
    } catch (e) {
      // Ignore parsing errors
    }
  }

  /// Pauses all active tasks.
  void pauseAllTasks() {
    for (var isolate in _isolatePool.isolateList) {
      String? taskId = isolate.task?.id;
      if (taskId != null) {
        _isolatePool.notifyIsolate(taskId, DownloadStatus.PAUSED);
      }
    }
  }

  /// Cancels and removes all tasks from the manager.
  void removeAllTask() {
    for (var isolate in _isolatePool.isolateList) {
      String? taskId = isolate.task?.id;
      if (taskId != null) {
        _isolatePool.notifyIsolate(taskId, DownloadStatus.CANCELLED);
        isolate.reset();
      }
    }
    allTasks.clear();
    _isolatePool.notifyTaskCountChange();
  }

  /// Checks if a task with the given match URL exists.
  bool isMatchUrlExit(String url) {
    return allTasks.where((task) => task.matchUrl == url).isNotEmpty;
  }

  /// Checks if a task with the given URL exists.
  bool isUrlExit(String url) {
    return allTasks.where((task) => task.uri.toString() == url).isNotEmpty;
  }

  /// Checks if a task with the given URL is currently downloading.
  bool isUrlDownloading(String url) {
    return activeTasks.where((task) => task.uri.toString() == url).isNotEmpty;
  }

  /// Disposes the manager and releases all resources.
  void dispose() {
    _isolatePool.dispose();
  }
}
