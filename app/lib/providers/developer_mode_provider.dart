import 'package:flutter/material.dart';
import 'package:friend_private/backend/http/api/users.dart';
import 'package:friend_private/backend/http/cloud_storage.dart';
import 'package:friend_private/backend/preferences.dart';
import 'package:friend_private/providers/base_provider.dart';
import 'package:friend_private/utils/alerts/app_snackbar.dart';
import 'package:friend_private/utils/analytics/mixpanel.dart';

class DeveloperModeProvider extends BaseProvider {
  final TextEditingController gcpCredentialsController = TextEditingController();
  final TextEditingController gcpBucketNameController = TextEditingController();
  final TextEditingController webhookOnMemoryCreated = TextEditingController();
  final TextEditingController webhookOnTranscriptReceived = TextEditingController();
  final TextEditingController webhookAudioBytes = TextEditingController();
  final TextEditingController webhookAudioBytesDelay = TextEditingController();
  final TextEditingController webhookWsAudioBytes = TextEditingController();

  bool savingSettingsLoading = false;

  bool loadingExportMemories = false;
  bool loadingImportMemories = false;

  bool localSyncEnabled = false;
  bool followUpQuestionEnabled = false;

  void initialize() {
    gcpCredentialsController.text = SharedPreferencesUtil().gcpCredentials;
    gcpBucketNameController.text = SharedPreferencesUtil().gcpBucketName;
    localSyncEnabled = SharedPreferencesUtil().localSyncEnabled;
    followUpQuestionEnabled = SharedPreferencesUtil().devModeJoanFollowUpEnabled;

    getUserWebhookUrl(type: 'audio_bytes').then((url) {
      List<dynamic> parts = url.split(',');
      if (parts.length == 2) {
        webhookAudioBytes.text = parts[0].toString();
        webhookAudioBytesDelay.text = parts[1].toString();
      } else {
        webhookAudioBytes.text = url;
        webhookAudioBytesDelay.text = '5';
      }
    });
    getUserWebhookUrl(type: 'realtime_transcript').then((url) => webhookOnTranscriptReceived.text = url);
    getUserWebhookUrl(type: 'memory_created').then((url) => webhookOnMemoryCreated.text = url);
    // getUserWebhookUrl(type: 'audio_bytes_websocket').then((url) => webhookWsAudioBytes.text = url);

    notifyListeners();
  }

  bool isValidUrl(String url) {
    const urlPattern = r'^(https?:\/\/)?([a-zA-Z0-9.-]+(:[a-zA-Z0-9.&%$-]+)*@)?'
        r'((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}'
        r'(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)|'
        r'([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,63}(:[0-9]+)?(\/.*)?$';
    return RegExp(urlPattern).hasMatch(url);
  }

  bool isValidWebSocketUrl(String url) {
    const webSocketPattern = r'^(wss?:\/\/)?([a-zA-Z0-9.-]+(:[a-zA-Z0-9.&%$-]+)*@)?'
        r'((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}'
        r'(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)|'
        r'([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,63}(:[0-9]+)?(\/.*)?$';
    return RegExp(webSocketPattern).hasMatch(url);
  }

  void saveSettings() async {
    if (savingSettingsLoading) return;
    savingSettingsLoading = true;
    notifyListeners();
    final prefs = SharedPreferencesUtil();

    if (gcpCredentialsController.text.isNotEmpty && gcpBucketNameController.text.isNotEmpty) {
      try {
        await authenticateGCP(base64: gcpCredentialsController.text.trim());
      } catch (e) {
        AppSnackbar.showSnackbarError(
          'Invalid GCP credentials or bucket name. Please check and try again.',
        );

        savingSettingsLoading = false;
        notifyListeners();

        return;
      }
    }

    // TODO: test openai + deepgram keys + bucket existence, before saving

    prefs.gcpCredentials = gcpCredentialsController.text.trim();
    prefs.gcpBucketName = gcpBucketNameController.text.trim();

    if (webhookAudioBytes.text.isNotEmpty && !isValidUrl(webhookAudioBytes.text)) {
      AppSnackbar.showSnackbarError('Invalid audio bytes webhook URL');
      savingSettingsLoading = false;
      notifyListeners();
      return;
    }
    if (webhookAudioBytes.text.isNotEmpty && webhookAudioBytesDelay.text.isEmpty) {
      webhookAudioBytesDelay.text = '5';
    }
    if (webhookOnTranscriptReceived.text.isNotEmpty && !isValidUrl(webhookOnTranscriptReceived.text)) {
      AppSnackbar.showSnackbarError('Invalid realtime transcript webhook URL');
      savingSettingsLoading = false;
      notifyListeners();
      return;
    }
    if (webhookOnMemoryCreated.text.isNotEmpty && !isValidUrl(webhookOnMemoryCreated.text)) {
      AppSnackbar.showSnackbarError('Invalid memory created webhook URL');
      savingSettingsLoading = false;
      notifyListeners();
      return;
    }

    // if (webhookWsAudioBytes.text.isNotEmpty && !isValidWebSocketUrl(webhookWsAudioBytes.text)) {
    //   AppSnackbar.showSnackbarError('Invalid audio bytes websocket URL');
    //   savingSettingsLoading = false;
    //   notifyListeners();
    //   return;
    // }

    var w1 = setUserWebhookUrl(
      type: 'audio_bytes',
      url: '${webhookAudioBytes.text.trim()},${webhookAudioBytesDelay.text.trim()}',
    );
    var w2 = setUserWebhookUrl(type: 'realtime_transcript', url: webhookOnTranscriptReceived.text.trim());
    var w3 = setUserWebhookUrl(type: 'memory_created', url: webhookOnMemoryCreated.text.trim());
    // var w4 = setUserWebhookUrl(type: 'audio_bytes_websocket', url: webhookWsAudioBytes.text.trim());
    await Future.wait([w1, w2, w3]);

    // Experimental
    prefs.localSyncEnabled = localSyncEnabled;
    prefs.devModeJoanFollowUpEnabled = followUpQuestionEnabled;

    MixpanelManager().settingsSaved(
      hasGCPCredentials: prefs.gcpCredentials.isNotEmpty,
      hasGCPBucketName: prefs.gcpBucketName.isNotEmpty,
    );
    savingSettingsLoading = false;
    notifyListeners();
    AppSnackbar.showSnackbar('Settings saved!');
  }

  void onLocalSyncEnabledChanged(var value) {
    localSyncEnabled = value;
    notifyListeners();
  }

  void onFollowUpQuestionChanged(var value) {
    followUpQuestionEnabled = value;
    notifyListeners();
  }
}
