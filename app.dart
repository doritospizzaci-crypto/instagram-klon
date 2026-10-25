import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'firebase_options.dart';

FirebaseFirestore get _db => FirebaseFirestore.instance;
String get _uid => FirebaseAuth.instance.currentUser!.uid;

final Map<String, Uint8List> _imgCache = {};
Uint8List _decode(String key, String b64) =>
    _imgCache.putIfAbsent(key, () => base64Decode(b64));

String _chatIdFor(String a, String b) {
  final ids = [a, b]..sort();
  return ids.join('_');
}

Future<String> _myUsername() async {
  final s = await _db.collection('users').doc(_uid).get();
  final n = s.data()?['username'];
  if (n is String && n.isNotEmpty) return n;
  return (FirebaseAuth.instance.currentUser!.email ?? 'kullanici')
      .split('@')
      .first;
}

void _snack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Instagram Klon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.hasData ? const MainShell() : const AuthPage();
      },
    );
  }
}

// ---------------------------------------------------------------- GİRİŞ

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text.trim(),
        );
      } else {
        final username = _username.text.trim().toLowerCase();
        if (username.length < 3) throw 'Kullanıcı adı en az 3 karakter olmalı';
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text.trim(),
        );
        await _db.collection('users').doc(cred.user!.uid).set({
          'username': username,
          'bio': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseAuthException catch (e) {
      _snack(context, e.message ?? 'Bir hata oluştu');
    } catch (e) {
      _snack(context, e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Text('Instagram Klon',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                if (!_isLogin) ...[
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(
                        labelText: 'Kullanıcı adı',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'E-posta', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Şifre', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isLogin ? 'Giriş yap' : 'Kayıt ol'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(_isLogin
                      ? 'Hesabın yok mu? Kayıt ol'
                      : 'Zaten hesabın var mı? Giriş yap'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- ANA İSKELET

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _ensureProfile();
  }

  // Profil belgesi yoksa oluştur (eski hesaplar için güvenlik)
  Future<void> _ensureProfile() async {
    try {
      final ref = _db.collection('users').doc(_uid);
      final snap = await ref.get();
      if (!snap.exists) {
        final email = FirebaseAuth.instance.currentUser!.email ?? 'kullanici';
        await ref.set({
          'username': email.split('@').first.toLowerCase(),
          'bio': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const FeedPage(),
          NewPostPage(onDone: () => setState(() => _index = 0)),
          const ChatsPage(),
          ProfilePage(uid: _uid, isTab: true),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Akış'),
          NavigationDestination(
              icon: Icon(Icons.add_box_outlined),
              selectedIcon: Icon(Icons.add_box),
              label: 'Paylaş'),
          NavigationDestination(
              icon: Icon(Icons.send_outlined),
              selectedIcon: Icon(Icons.send),
              label: 'Mesajlar'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil'),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final double radius;
  const _Avatar(this.name, {this.radius = 18});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
    );
  }
}

// ---------------------------------------------------------------- AKIŞ

class FeedPage extends StatelessWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Instagram Klon',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection('posts')
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Hata: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
                child: Text('Henüz paylaşım yok. İlk paylaşımı sen yap!'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (c, i) =>
                PostCard(id: docs[i].id, data: docs[i].data()),
          );
        },
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  const PostCard({super.key, required this.id, required this.data});

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paylaşım silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) {
      await _db.collection('posts').doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final likes = List<String>.from(data['likes'] ?? []);
    final liked = likes.contains(_uid);
    final username = (data['username'] ?? '') as String;
    final ownerUid = (data['uid'] ?? '') as String;
    final caption = (data['caption'] ?? '') as String;
    final image = (data['image'] ?? '') as String;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: _Avatar(username),
          title: Text(username,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProfilePage(uid: ownerUid)),
          ),
          trailing: ownerUid == _uid
              ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context),
                )
              : null,
        ),
        if (image.isNotEmpty)
          Image.memory(
            _decode(id, image),
            width: double.infinity,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        Row(
          children: [
            IconButton(
              icon: Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                color: liked ? Colors.red : null,
              ),
              onPressed: () => _db.collection('posts').doc(id).update({
                'likes': liked
                    ? FieldValue.arrayRemove([_uid])
                    : FieldValue.arrayUnion([_uid]),
              }),
            ),
            Text('${likes.length} beğeni'),
          ],
        ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$username ',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: caption),
            ])),
          ),
        const SizedBox(height: 8),
        const Divider(),
      ],
    );
  }
}

// ---------------------------------------------------------------- PAYLAŞ

class NewPostPage extends StatefulWidget {
  final VoidCallback onDone;
  const NewPostPage({super.key, required this.onDone});

  @override
  State<NewPostPage> createState() => _NewPostPageState();
}

class _NewPostPageState extends State<NewPostPage> {
  final _caption = TextEditingController();
  Uint8List? _bytes;
  bool _loading = false;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 60,
    );
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() => _bytes = b);
  }

  Future<void> _share() async {
    if (_bytes == null) return;
    final b64 = base64Encode(_bytes!);
    if (b64.length > 900000) {
      _snack(context, 'Fotoğraf çok büyük, başka bir tane dene');
      return;
    }
    setState(() => _loading = true);
    try {
      final name = await _myUsername();
      await _db.collection('posts').add({
        'uid': _uid,
        'username': name,
        'image': b64,
        'caption': _caption.text.trim(),
        'likes': [],
        'createdAt': FieldValue.serverTimestamp(),
      });
      _caption.clear();
      setState(() => _bytes = null);
      widget.onDone();
    } catch (e) {
      _snack(context, 'Paylaşılamadı: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni paylaşım')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: _pick,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _bytes == null
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 56),
                          SizedBox(height: 8),
                          Text('Fotoğraf seçmek için dokun'),
                        ],
                      ),
                    )
                  : Image.memory(_bytes!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _caption,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
                labelText: 'Açıklama yaz...', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: (_bytes == null || _loading) ? null : _share,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Paylaş'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- PROFİL

class ProfilePage extends StatelessWidget {
  final String uid;
  final bool isTab;
  const ProfilePage({super.key, required this.uid, this.isTab = false});

  Future<void> _editBio(BuildContext context, String current) async {
    final c = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Biyografi'),
        content: TextField(controller: c, maxLength: 150, maxLines: 3),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok == true) {
      await _db.collection('users').doc(uid).update({'bio': c.text.trim()});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMe = uid == _uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        automaticallyImplyLeading: !isTab,
        actions: isMe
            ? [
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                ),
              ]
            : null,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _db.collection('users').doc(uid).snapshots(),
        builder: (context, userSnap) {
          final u = userSnap.data?.data() ?? {};
          final username = (u['username'] ?? '') as String;
          final bio = (u['bio'] ?? '') as String;

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                _db.collection('posts').where('uid', isEqualTo: uid).snapshots(),
            builder: (context, postSnap) {
              final docs = (postSnap.data?.docs ?? []).toList()
                ..sort((a, b) {
                  final ta = a.data()['createdAt'];
                  final tb = b.data()['createdAt'];
                  final ma = ta is Timestamp ? ta.millisecondsSinceEpoch : 1 << 50;
                  final mb = tb is Timestamp ? tb.millisecondsSinceEpoch : 1 << 50;
                  return mb.compareTo(ma);
                });

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _Avatar(username, radius: 36),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(username,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                              Text('${docs.length} paylaşım'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (bio.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                          alignment: Alignment.centerLeft, child: Text(bio)),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: isMe
                          ? OutlinedButton(
                              onPressed: () => _editBio(context, bio),
                              child: const Text('Biyografiyi düzenle'),
                            )
                          : FilledButton.tonal(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(
                                      otherUid: uid, otherName: username),
                                ),
                              ),
                              child: const Text('Mesaj gönder'),
                            ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: docs.isEmpty
                        ? const Center(child: Text('Henüz paylaşım yok'))
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 2,
                            ),
                            itemCount: docs.length,
                            itemBuilder: (c, i) {
                              final img =
                                  (docs[i].data()['image'] ?? '') as String;
                              if (img.isEmpty) return const SizedBox();
                              return Image.memory(
                                _decode(docs[i].id, img),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- MESAJLAR

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mesajlar')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserSearchPage()),
        ),
        child: const Icon(Icons.edit),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection('chats')
            .where('users', arrayContains: _uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Hata: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs.toList()
            ..sort((a, b) {
              final ta = a.data()['lastTime'];
              final tb = b.data()['lastTime'];
              final ma = ta is Timestamp ? ta.millisecondsSinceEpoch : 1 << 50;
              final mb = tb is Timestamp ? tb.millisecondsSinceEpoch : 1 << 50;
              return mb.compareTo(ma);
            });
          if (docs.isEmpty) {
            return const Center(
                child: Text('Henüz mesaj yok.\nSağ alttaki butondan başla.',
                    textAlign: TextAlign.center));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (c, i) {
              final d = docs[i].data();
              final users = List<String>.from(d['users'] ?? []);
              final otherUid =
                  users.firstWhere((x) => x != _uid, orElse: () => '');
              final names = Map<String, dynamic>.from(d['usernames'] ?? {});
              final otherName = (names[otherUid] ?? 'Kullanıcı') as String;
              return ListTile(
                leading: _Avatar(otherName, radius: 22),
                title: Text(otherName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text((d['lastMessage'] ?? '') as String,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ChatPage(otherUid: otherUid, otherName: otherName),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Kullanıcı ara', border: InputBorder.none),
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('users').limit(200).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Hata: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs
              .where((d) =>
                  d.id != _uid &&
                  ((d.data()['username'] ?? '') as String).contains(_q))
              .toList();
          if (docs.isEmpty) {
            return const Center(child: Text('Kullanıcı bulunamadı'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (c, i) {
              final name = (docs[i].data()['username'] ?? '') as String;
              return ListTile(
                leading: _Avatar(name),
                title: Text(name),
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ChatPage(otherUid: docs[i].id, otherName: name),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final String otherUid;
  final String otherName;
  const ChatPage({super.key, required this.otherUid, required this.otherName});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _text = TextEditingController();

  String get _chatId => _chatIdFor(_uid, widget.otherUid);

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    try {
      final me = await _myUsername();
      final chatRef = _db.collection('chats').doc(_chatId);
      await chatRef.set({
        'users': [_uid, widget.otherUid],
        'usernames': {_uid: me, widget.otherUid: widget.otherName},
        'lastMessage': text,
        'lastTime': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await chatRef.collection('messages').add({
        'from': _uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _snack(context, 'Gönderilemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _Avatar(widget.otherName),
            const SizedBox(width: 12),
            Text(widget.otherName),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('chats')
                  .doc(_chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: Text('Henüz mesaj yok'));
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('Henüz mesaj yok'));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (c, i) {
                    final m = docs[i].data();
                    final mine = m['from'] == _uid;
                    final cs = Theme.of(context).colorScheme;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: mine
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text((m['text'] ?? '') as String),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Mesaj yaz...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
