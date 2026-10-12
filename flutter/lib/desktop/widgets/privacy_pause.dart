import 'dart:async';
import 'package:flutter/material.dart';

class PrivacyPauseControl extends StatefulWidget {
  const PrivacyPauseControl(
      {super.key,
      required this.paused,
      required this.confirmed,
      required this.onChanged,
      required this.pauseLabel,
      required this.resumeLabel,
      required this.pendingLabel,
      required this.errorLabel});

  final bool paused;
  final bool confirmed;
  final ValueChanged<bool> onChanged;
  final String pauseLabel;
  final String resumeLabel;
  final String pendingLabel;
  final String errorLabel;

  @override
  State<PrivacyPauseControl> createState() => _PrivacyPauseControlState();
}

class _PrivacyPauseControlState extends State<PrivacyPauseControl> {
  bool? _requested;
  bool _timedOut = false;
  Timer? _timeout;

  @override
  void didUpdateWidget(covariant PrivacyPauseControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_requested == widget.paused || !widget.confirmed) {
      _timeout?.cancel();
      _requested = null;
      _timedOut = false;
    }
  }

  void _change() {
    setState(() {
      _requested = !widget.paused;
      _timedOut = false;
    });
    _timeout = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() {
        _requested = null;
        _timedOut = true;
      });
    });
    widget.onChanged(_requested!);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _requested != null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!widget.confirmed || _timedOut)
        Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(widget.errorLabel,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            onPressed: pending ? null : _change,
            icon: pending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(widget.paused ? Icons.play_arrow : Icons.pause),
            label: Text(
                pending
                    ? widget.pendingLabel
                    : widget.paused
                        ? widget.resumeLabel
                        : widget.pauseLabel,
                maxLines: 2,
                textAlign: TextAlign.center),
          )),
    ]);
  }
}

class PrivacyPauseCover extends StatelessWidget {
  const PrivacyPauseCover({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => AbsorbPointer(
        child: ColoredBox(
            color: const Color(0xff202124),
            child: Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.visibility_off,
                          size: 48, color: Colors.white70),
                      const SizedBox(height: 16),
                      Text(label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 18, color: Colors.white)),
                    ])))),
      );
}
