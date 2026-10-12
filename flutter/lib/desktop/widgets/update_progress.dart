import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

final _isExtracting = false.obs;
bool _updateInProgress = false;

Future<void> handleUpdate(String releasePageUrl) async {
  if (_updateInProgress) return;
  _updateInProgress = true;
  if (isWindows && bind.isCustomClient() && !bind.mainIsInstalled()) {
    final confirmed = await gFFI.dialogManager.show<bool>(
      (setState, close, context) => CustomAlertDialog(
        title: Text(translate('Install')),
        content: Text(translate('install_tip')),
        actions: [
          dialogButton('Cancel', onPressed: () => close(false), isOutline: true),
          dialogButton('Install', onPressed: () => close(true)),
        ],
      ),
    );
    if (confirmed != true) {
      _updateInProgress = false;
      return;
    }
  }
  _isExtracting.value = false;
  String downloadUrl = releasePageUrl.replaceAll('tag', 'download');
  String version = downloadUrl.substring(downloadUrl.lastIndexOf('/') + 1);
  final String downloadFile =
      bind.mainGetCommonSync(key: 'download-file-$version');
  if (downloadFile.startsWith('error:')) {
    _updateInProgress = false;
    final error = downloadFile.replaceFirst('error:', '');
    msgBox(gFFI.sessionId, 'custom-nocancel-nook-hasclose', 'Error', error,
        bind.isCustomClient() ? '' : releasePageUrl, gFFI.dialogManager);
    return;
  }
  downloadUrl = '$downloadUrl/$downloadFile';
  platformFFI.registerEventHandler('update-install-error', 'update-install-error',
      (Map<String, dynamic> evt) async {
    _updateInProgress = false;
    msgBox(gFFI.sessionId, 'custom-nocancel-nook-hasclose', 'Error',
        evt['error']?.toString() ?? 'Failed', '', gFFI.dialogManager);
  }, replace: true);

  SimpleWrapper downloadId = SimpleWrapper(downloadUrl);
  SimpleWrapper<Future<void> Function()> onCanceled = SimpleWrapper(() async {});
  gFFI.dialogManager.dismissAll();
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
        title: Obx(() => Text(translate(_isExtracting.isTrue
            ? 'Preparing for installation ...'
            : 'Downloading {$appName}'))),
        content:
            UpdateProgress(releasePageUrl, downloadUrl, downloadId, onCanceled)
                .marginSymmetric(horizontal: 8)
                .paddingOnly(top: 12),
        actions: [
          if (_isExtracting.isFalse) dialogButton(translate('Cancel'), onPressed: () async {
            await onCanceled.value();
            await bind.mainSetCommon(
                key: 'cancel-downloader', value: downloadId.value);
            // Wait for the downloader to be removed.
            for (int i = 0; i < 10; i++) {
              await Future.delayed(const Duration(milliseconds: 300));
              final isCanceled = 'error:Downloader not found' ==
                  await bind.mainGetCommon(
                      key: 'download-data-${downloadId.value}');
              if (isCanceled) {
                break;
              }
            }
            close();
            _updateInProgress = false;
          }, isOutline: true),
        ]);
  });
}

class UpdateProgress extends StatefulWidget {
  final String releasePageUrl;
  final String downloadUrl;
  final SimpleWrapper downloadId;
  final SimpleWrapper onCanceled;
  UpdateProgress(
      this.releasePageUrl, this.downloadUrl, this.downloadId, this.onCanceled,
      {Key? key})
      : super(key: key);

  @override
  State<UpdateProgress> createState() => UpdateProgressState();
}

class UpdateProgressState extends State<UpdateProgress> {
  Timer? _timer;
  int? _totalSize;
  int _downloadedSize = 0;
  bool _downloadFinished = false;
  bool _canceled = false;
  int _getDataFailedCount = 0;
  final String _eventKeyDownloadNewVersion = 'download-new-version';
  final String _eventKeyExtractUpdateDmg = 'extract-update-dmg';

  @override
  void initState() {
    super.initState();
    platformFFI.registerEventHandler(_eventKeyDownloadNewVersion,
        _eventKeyDownloadNewVersion, handleDownloadNewVersion,
        replace: true);
    final downloadStarted = bind.mainSetCommon(
        key: 'download-new-version', value: widget.downloadUrl);
    widget.onCanceled.value = () async {
      _canceled = true;
      cancelQueryTimer();
      await downloadStarted;
    };
    downloadStarted.then((_) {
      if (!mounted && !_downloadFinished) {
        bind.mainSetCommon(key: 'cancel-downloader', value: widget.downloadUrl);
      }
    });
    if (isMacOS) {
      platformFFI.registerEventHandler(_eventKeyExtractUpdateDmg,
          _eventKeyExtractUpdateDmg, handleExtractUpdateDmg,
          replace: true);
    }
  }

  @override
  void dispose() {
    cancelQueryTimer();
    if (!_downloadFinished) {
      _canceled = true;
      _updateInProgress = false;
      if (widget.downloadId.value.isNotEmpty) {
        bind.mainSetCommon(key: 'cancel-downloader', value: widget.downloadId.value);
      }
    }
    platformFFI.unregisterEventHandler(
        _eventKeyDownloadNewVersion, _eventKeyDownloadNewVersion);
    if (isMacOS) {
      platformFFI.unregisterEventHandler(
          _eventKeyExtractUpdateDmg, _eventKeyExtractUpdateDmg);
    }
    super.dispose();
  }

  void cancelQueryTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> handleDownloadNewVersion(Map<String, dynamic> evt) async {
    if (_canceled) return;
    if (evt.containsKey('id')) {
      widget.downloadId.value = evt['id'] as String;
      _timer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
        _updateDownloadData();
      });
    } else {
      if (evt.containsKey('error')) {
        _onError(evt['error'] as String);
      } else {
        // unreachable
        _onError('$evt');
      }
    }
  }

  // `isExtractDmg` is true when handling extract-update-dmg event.
  // It's a rare case that the dmg file is corrupted and cannot be extracted.
  void _onError(String error, {bool isExtractDmg = false}) {
    _updateInProgress = false;
    cancelQueryTimer();

    debugPrint(
        '${isExtractDmg ? "Extract" : "Download"} new version error: $error');
    final msgBoxType = 'custom-nocancel-nook-hasclose';
    final msgBoxTitle = 'Error';
    final msgBoxText = bind.isCustomClient()
        ? 'Failed'
        : 'download-new-version-failed-tip';
    final dialogManager = gFFI.dialogManager;

    close() {
      dialogManager.dismissAll();
    }

    jumplink() {
      launchUrl(Uri.parse(widget.releasePageUrl));
      dialogManager.dismissAll();
    }

    retry() {
      dialogManager.dismissAll();
      handleUpdate(widget.releasePageUrl);
    }

    final List<Widget> buttons = [
      if (!bind.isCustomClient()) dialogButton('Download', onPressed: jumplink),
      if (!isExtractDmg) dialogButton('Retry', onPressed: retry),
      dialogButton('Close', onPressed: close),
    ];
    dialogManager.dismissAll();
    dialogManager.show(
      (setState, close, context) => CustomAlertDialog(
        title: null,
        content: SelectionArea(
            child: msgboxContent(msgBoxType, msgBoxTitle,
                '${translate(msgBoxText)}\n\n$error')),
        actions: buttons,
      ),
      tag: '$msgBoxType-$msgBoxTitle-$msgBoxTitle',
    );
  }

  void _updateDownloadData() {
    String err = '';
    String downloadData =
        bind.mainGetCommonSync(key: 'download-data-${widget.downloadId.value}');
    if (downloadData.startsWith('error:')) {
      err = downloadData.substring('error:'.length);
    } else {
      try {
        jsonDecode(downloadData).forEach((key, value) {
          if (key == 'total_size') {
            if (value != null && value is int) {
              _totalSize = value;
            }
          } else if (key == 'downloaded_size') {
            _downloadedSize = value as int;
          } else if (key == 'finished') {
            _downloadFinished = value == true;
          } else if (key == 'error') {
            if (value != null) {
              err = value.toString();
            }
          }
        });
      } catch (e) {
        _getDataFailedCount += 1;
        debugPrint(
            'Failed to get download data ${widget.downloadUrl}, error $e');
        if (_getDataFailedCount > 3) {
          err = e.toString();
        }
      }
    }
    if (err != '') {
      _onError(err);
    } else {
      if (_downloadFinished &&
          _totalSize != null &&
          _downloadedSize >= _totalSize!) {
        cancelQueryTimer();
        bind.mainSetCommon(
            key: 'remove-downloader', value: widget.downloadId.value);
        if (_totalSize == 0) {
          _onError('The download file size is 0.');
        } else {
          setState(() {});
          if (isMacOS) {
            bind.mainSetCommon(
                key: 'extract-update-dmg', value: widget.downloadUrl);
            _isExtracting.value = true;
          } else {
            updateMsgBox();
          }
        }
      } else {
        setState(() {});
      }
    }
  }

  void updateMsgBox() {
    msgBox(
      gFFI.sessionId,
      'custom-nocancel',
      '{$appName} Update',
      '{$appName}-to-update-tip',
      '',
      gFFI.dialogManager,
      onSubmit: () {
        debugPrint('Downloaded, update to new version now');
        bind.mainSetCommon(key: 'update-me', value: widget.downloadUrl);
      },
      submitTimeout: 5,
    );
  }

  Future<void> handleExtractUpdateDmg(Map<String, dynamic> evt) async {
    _isExtracting.value = false;
    if (evt.containsKey('err') && (evt['err'] as String).isNotEmpty) {
      _onError(evt['err'] as String, isExtractDmg: true);
    } else {
      updateMsgBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    getValue() => _totalSize == null
        ? 0.0
        : (_totalSize == 0 ? 1.0 : _downloadedSize / _totalSize!);
    return LinearProgressIndicator(
      value: _isExtracting.isTrue ? null : getValue(),
      minHeight: 20,
      borderRadius: BorderRadius.circular(5),
      backgroundColor: Colors.grey[300],
      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
    );
  }
}
