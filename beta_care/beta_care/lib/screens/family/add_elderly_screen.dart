import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/family_provider.dart';

/// Section 3. The elderly person still has to approve this from their own
/// Beta AI app before the link becomes ACTIVE - this screen only sends the
/// request.
class AddElderlyScreen extends StatefulWidget {
  const AddElderlyScreen({super.key});

  @override
  State<AddElderlyScreen> createState() => _AddElderlyScreenState();
}

class _AddElderlyScreenState extends State<AddElderlyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  String _relationship = 'Son';
  bool _isSubmitting = false;

  static const _relationshipOptions = ['Son', 'Daughter', 'Spouse', 'Grandchild', 'Caregiver', 'Other'];

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    final ok = await context.read<FamilyProvider>().inviteElderly(
          invitationCode: _codeController.text.trim(),
          relationshipLabel: _relationship,
        );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent. Waiting for them to approve it.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final family = context.watch<FamilyProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Add elderly connection')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ask them to open their Beta AI app and share their invitation code with you.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Invitation code'),
                  validator: (v) => (v == null || v.trim().length < 4) ? 'Enter a valid invitation code' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _relationship,
                  decoration: const InputDecoration(labelText: 'Your relationship to them'),
                  items: _relationshipOptions
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setState(() => _relationship = v ?? _relationship),
                ),
                if (family.error != null) ...[
                  const SizedBox(height: 12),
                  Text(family.error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send request'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
