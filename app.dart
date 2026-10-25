import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'firebase_options.dart';

typedef J = Map<String, dynamic>;
typedef QS = QuerySnapshot<Map<String, dynamic>>;
typedef DS = DocumentSnapshot<Map<String, dynamic>>;
typedef QD = QueryDocumentSnapshot<Map<String, dynamic>>;

FirebaseFirestore get _db => FirebaseFirestore.instance;
String get _uid => FirebaseAuth.instance.currentUser!.uid;

// ---------------------------------------------------------------- YARDIMCILAR

final Map<String, Uint8List> _imgCache = {};
Uint8List _decode(String key, String b64) =>
    _imgCache.putIfAbsent(key, () => base64Decode(b64));

final Map<String, J> _userCache = {};
Future<J> _getUser(String uid) async {
  final c = _userCache[uid];
  if (c != null) return c;
  final s = await _db.collection('users').doc(uid).get();
  final d = s.data() ?? <String, dynamic>{};
  _userCache[uid] = d;
  return d;
}

int _ms(dynamic t) => t is Timestamp ? t.millisecondsSinceEpoch : 1 << 50;

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

Future<String?> _pickB64({double w = 800, int q = 60}) async {
  final x = await ImagePicker()
      .pickImage(source: ImageSource.gallery, maxWidth: w, imageQuality: q);
  if (x == null) return null;
  return base64Encode(await x.readAsBytes());
}

Future<bool> _confirm(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet')),
      ],
    ),
  );
  return ok == true;
}

void _push(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));

// ---------------------------------------------------------------- BAŞLANGIÇ

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
          'photo': '',
          'followers': [],
          'following': [],
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
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const FeedPage(),
      const ExplorePage(),
      NewPostPage(onDone: () => setState(() => _index = 0)),
      const ChatsPage(),
      ProfilePage(uid: _uid, isTab: true),
    ];
    _ensureProfile();
  }

  Future<void> _ensureProfile() async {
    try {
      final ref = _db.collection('users').doc(_uid);
      final snap = await ref.get();
      if (!snap.exists) {
        final email = FirebaseAuth.instance.currentUser!.email ?? 'kullanici';
        await ref.set({
          'username': email.split('@').first.toLowerCase(),
          'bio': '',
          'photo': '',
          'followers': [],
          'following': [],
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        final d = snap.data()!;
        final fix = <String, dynamic>{};
        if (d['followers'] == null) fix['followers'] = [];
        if (d['following'] == null) fix['following'] = [];
        if (fix.isNotEmpty) await ref.update(fix);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Akış'),
          NavigationDestination(
              icon: Icon(Icons.search),
              selectedIcon: Icon(Icons.manage_search),
              label: 'Keşfet'),
          NavigationDestination(
              icon: Icon(Icons.add_box_outlined),
              selectedIcon: Icon(Icons.add_box),
              label: 'Paylaş'),
          NavigationDestination(
              icon: Icon(Icons.send_outlined),
              selectedIcon: Icon(Icons.send),
              label: 'Mesaj'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil'),
        ],
      ),
    );
  }
}

// Kullanıcının profil fotoğrafı (yoksa harf)
class UserAvatar extends StatelessWidget {
  final String uid;
  final String name;
  final double radius;
  const UserAvatar(
      {super.key, required this.uid, required this.name, this.radius = 18});

  Widget _circle(J d) {
    final photo = (d['photo'] ?? '') as String;
    if (photo.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: MemoryImage(_decode('ph_$uid${photo.length}', photo)),
      );
    }
    return CircleAvatar(
      radius: radius,
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _userCache[uid];
    if (c != null) return _circle(c);
    return FutureBuilder<J>(
      future: _getUser(uid),
      builder: (context, s) => _circle(s.data ?? {}),
    );
  }
}

// ---------------------------------------------------------------- AKIŞ

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  late final Stream<DS> _me = _db.collection('users').doc(_uid).snapshots();
  late final Stream<QS> _posts = _db
      .collection('posts')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Instagram Klon',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<DS>(
        stream: _me,
        builder: (context, meSnap) {
          final following =
              List<String>.from(meSnap.data?.data()?['following'] ?? []);
          final visible = <String>{...following, _uid};
          return StreamBuilder<QS>(
            stream: _posts,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Hata: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs
                  .where((d) => visible.contains(d.data()['uid']))
                  .toList();
              return ListView.builder(
                itemCount: docs.length + (docs.isEmpty ? 2 : 1),
                itemBuilder: (c, i) {
                  if (i == 0) return StoriesBar(visible: visible);
                  if (docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Akışın boş.\nKeşfet sekmesinden insanları takip et ya da ilk paylaşımı yap!',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final d = docs[i - 1];
                  return PostCard(id: d.id, data: d.data());
                },
              );
            },
          );
        },
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  final String id;
  final J data;
  const PostCard({super.key, required this.id, required this.data});

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
          leading: UserAvatar(uid: ownerUid, name: username),
          title: Text(username,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () => _push(context, ProfilePage(uid: ownerUid)),
          trailing: ownerUid == _uid
              ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await _confirm(context, 'Paylaşım silinsin mi?')) {
                      await _db.collection('posts').doc(id).delete();
                    }
                  },
                )
              : null,
        ),
        if (image.isNotEmpty)
          Image.memory(_decode(id, image),
              width: double.infinity, fit: BoxFit.cover, gaplessPlayback: true),
        Row(
          children: [
            IconButton(
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? Colors.red : null),
              onPressed: () => _db.collection('posts').doc(id).update({
                'likes': liked
                    ? FieldValue.arrayRemove([_uid])
                    : FieldValue.arrayUnion([_uid]),
              }),
            ),
            Text('${likes.length} beğeni'),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.mode_comment_outlined),
              onPressed: () => _push(context, CommentsPage(postId: id)),
            ),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton(
            onPressed: () => _push(context, CommentsPage(postId: id)),
            child: const Text('Yorumları gör / yaz'),
          ),
        ),
        const Divider(),
      ],
    );
  }
}

class PostDetailPage extends StatelessWidget {
  final String id;
  const PostDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paylaşım')),
      body: StreamBuilder<DS>(
        stream: _db.collection('posts').doc(id).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!.data();
          if (d == null) return const Center(child: Text('Paylaşım silinmiş'));
          return SingleChildScrollView(child: PostCard(id: id, data: d));
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- HİKAYELER

class StoriesBar extends StatefulWidget {
  final Set<String> visible;
  const StoriesBar({super.key, required this.visible});

  @override
  State<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<StoriesBar> {
  late final Stream<QS> _stories = _db
      .collection('stories')
      .where('createdAt',
          isGreaterThan: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: 24))))
      .snapshots();

  Future<void> _addStory() async {
    final b64 = await _pickB64();
    if (b64 == null) return;
    if (b64.length > 900000) {
      if (mounted) _snack(context, 'Fotoğraf çok büyük');
      return;
    }
    try {
      await _db.collection('stories').add({
        'uid': _uid,
        'username': await _myUsername(),
        'image': b64,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) _snack(context, 'Hikaye paylaşılamadı: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QS>(
      stream: _stories,
      builder: (context, snap) {
        final byUser = <String, List<QD>>{};
        for (final d in snap.data?.docs ?? <QD>[]) {
          final u = (d.data()['uid'] ?? '') as String;
          if (!widget.visible.contains(u)) continue;
          (byUser[u] ??= []).add(d);
        }
        for (final v in byUser.values) {
          v.sort((a, b) =>
              _ms(a.data()['createdAt']).compareTo(_ms(b.data()['createdAt'])));
        }
        final others = byUser.keys.where((k) => k != _uid).toList();
        final mine = byUser[_uid];

        return SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            children: [
              _StoryBubble(
                uid: _uid,
                name: 'Hikayen',
                ring: mine != null,
                plus: true,
                onTap: () {
                  if (mine == null) {
                    _addStory();
                  } else {
                    showModalBottomSheet(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.play_circle_outline),
                              title: const Text('Hikayeni izle'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _push(context, StoryViewer(docs: mine));
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.add_a_photo_outlined),
                              title: const Text('Yeni hikaye ekle'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _addStory();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),
              for (final u in others)
                _StoryBubble(
                  uid: u,
                  name: (byUser[u]!.first.data()['username'] ?? '') as String,
                  ring: true,
                  plus: false,
                  onTap: () => _push(context, StoryViewer(docs: byUser[u]!)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StoryBubble extends StatelessWidget {
  final String uid;
  final String name;
  final bool ring;
  final bool plus;
  final VoidCallback onTap;
  const _StoryBubble({
    required this.uid,
    required this.name,
    required this.ring,
    required this.plus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ring
                    ? const LinearGradient(
                        colors: [Colors.pink, Colors.orange],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft)
                    : null,
                border: ring ? null : Border.all(color: Colors.black26),
              ),
              child: Stack(
                children: [
                  UserAvatar(uid: uid, name: name, radius: 28),
                  if (plus)
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: Colors.blue,
                        child: Icon(Icons.add, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 70,
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class StoryViewer extends StatefulWidget {
  final List<QD> docs;
  const StoryViewer({super.key, required this.docs});

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  final _pc = PageController();
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final docs = widget.docs;
    final cur = docs[_i].data();
    final isMine = cur['uid'] == _uid;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx > w / 2) {
            if (_i < docs.length - 1) {
              _pc.nextPage(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut);
            } else {
              Navigator.pop(context);
            }
          } else if (_i > 0) {
            _pc.previousPage(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut);
          }
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _pc,
              itemCount: docs.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (c, i) => Center(
                child: Image.memory(
                  _decode(docs[i].id, (docs[i].data()['image'] ?? '') as String),
                  fit: BoxFit.contain,
                  width: double.infinity,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (int i = 0; i < docs.length; i++)
                          Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              color: i <= _i ? Colors.white : Colors.white24,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        UserAvatar(
                            uid: (cur['uid'] ?? '') as String,
                            name: (cur['username'] ?? '') as String,
                            radius: 16),
                        const SizedBox(width: 8),
                        Text((cur['username'] ?? '') as String,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (isMine)
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.white),
                            onPressed: () async {
                              await _db
                                  .collection('stories')
                                  .doc(docs[_i].id)
                                  .delete();
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
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

// ---------------------------------------------------------------- YORUMLAR

class CommentsPage extends StatefulWidget {
  final String postId;
  const CommentsPage({super.key, required this.postId});

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final _text = TextEditingController();
  late final Stream<QS> _stream = _db
      .collection('posts')
      .doc(widget.postId)
      .collection('comments')
      .orderBy('createdAt')
      .snapshots();

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    try {
      await _db
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .add({
        'uid': _uid,
        'username': await _myUsername(),
        'text': t,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) _snack(context, 'Yorum gönderilemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yorumlar')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QS>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Hata: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('Henüz yorum yok'));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (c, i) {
                    final d = docs[i].data();
                    final name = (d['username'] ?? '') as String;
                    final uid = (d['uid'] ?? '') as String;
                    return ListTile(
                      leading: UserAvatar(uid: uid, name: name),
                      title: Text.rich(TextSpan(children: [
                        TextSpan(
                            text: '$name ',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: (d['text'] ?? '') as String),
                      ])),
                      trailing: uid == _uid
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => docs[i].reference.delete(),
                            )
                          : null,
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
                      decoration: InputDecoration(
                        hintText: 'Yorum yaz...',
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

// ---------------------------------------------------------------- KEŞFET

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  String _q = '';
  late final Stream<QS> _posts = _db
      .collection('posts')
      .orderBy('createdAt', descending: true)
      .limit(60)
      .snapshots();
  late final Stream<QS> _users = _db.collection('users').limit(200).snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: const InputDecoration(
              hintText: 'Kullanıcı ara',
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search)),
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
        ),
      ),
      body: _q.isEmpty
          ? StreamBuilder<QS>(
              stream: _posts,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('Henüz paylaşım yok'));
                }
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2),
                  itemCount: docs.length,
                  itemBuilder: (c, i) {
                    final img = (docs[i].data()['image'] ?? '') as String;
                    if (img.isEmpty) return const SizedBox();
                    return GestureDetector(
                      onTap: () => _push(context, PostDetailPage(id: docs[i].id)),
                      child: Image.memory(_decode(docs[i].id, img),
                          fit: BoxFit.cover, gaplessPlayback: true),
                    );
                  },
                );
              },
            )
          : StreamBuilder<QS>(
              stream: _users,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs
                    .where((d) =>
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
                      leading: UserAvatar(uid: docs[i].id, name: name),
                      title: Text(name),
                      onTap: () => _push(context, ProfilePage(uid: docs[i].id)),
                    );
                  },
                );
              },
            ),
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
  String? _b64;
  Uint8List? _bytes;
  bool _loading = false;

  Future<void> _pick() async {
    final s = await _pickB64();
    if (s == null) return;
    setState(() {
      _b64 = s;
      _bytes = base64Decode(s);
    });
  }

  Future<void> _share() async {
    if (_b64 == null) return;
    if (_b64!.length > 900000) {
      _snack(context, 'Fotoğraf çok büyük, başka bir tane dene');
      return;
    }
    setState(() => _loading = true);
    try {
      await _db.collection('posts').add({
        'uid': _uid,
        'username': await _myUsername(),
        'image': _b64,
        'caption': _caption.text.trim(),
        'likes': [],
        'createdAt': FieldValue.serverTimestamp(),
      });
      _caption.clear();
      setState(() {
        _b64 = null;
        _bytes = null;
      });
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
              onPressed: (_b64 == null || _loading) ? null : _share,
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

class ProfilePage extends StatefulWidget {
  final String uid;
  final bool isTab;
  const ProfilePage({super.key, required this.uid, this.isTab = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final Stream<DS> _user =
      _db.collection('users').doc(widget.uid).snapshots();
  late final Stream<QS> _posts =
      _db.collection('posts').where('uid', isEqualTo: widget.uid).snapshots();

  Future<void> _editBio(String current) async {
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
      await _db.collection('users').doc(_uid).update({'bio': c.text.trim()});
      _userCache.remove(_uid);
    }
  }

  Future<void> _changePhoto() async {
    final b64 = await _pickB64(w: 300, q: 60);
    if (b64 == null) return;
    try {
      await _db.collection('users').doc(_uid).update({'photo': b64});
      _userCache.remove(_uid);
    } catch (e) {
      if (mounted) _snack(context, 'Fotoğraf değiştirilemedi: $e');
    }
  }

  Future<void> _toggleFollow(bool following) async {
    try {
      final batch = _db.batch();
      batch.update(_db.collection('users').doc(_uid), {
        'following': following
            ? FieldValue.arrayRemove([widget.uid])
            : FieldValue.arrayUnion([widget.uid]),
      });
      batch.update(_db.collection('users').doc(widget.uid), {
        'followers': following
            ? FieldValue.arrayRemove([_uid])
            : FieldValue.arrayUnion([_uid]),
      });
      await batch.commit();
    } catch (e) {
      if (mounted) _snack(context, 'İşlem yapılamadı: $e');
    }
  }

  Widget _stat(String n, String l) => Column(
        children: [
          Text(n,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(l, style: const TextStyle(fontSize: 12)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final isMe = widget.uid == _uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        automaticallyImplyLeading: !widget.isTab,
        actions: isMe
            ? [
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                ),
              ]
            : null,
      ),
      body: StreamBuilder<DS>(
        stream: _user,
        builder: (context, userSnap) {
          final u = userSnap.data?.data() ?? <String, dynamic>{};
          final username = (u['username'] ?? '') as String;
          final bio = (u['bio'] ?? '') as String;
          final photo = (u['photo'] ?? '') as String;
          final followers = List<String>.from(u['followers'] ?? []);
          final following = List<String>.from(u['following'] ?? []);
          final iFollow = followers.contains(_uid);

          return StreamBuilder<QS>(
            stream: _posts,
            builder: (context, postSnap) {
              final docs = (postSnap.data?.docs ?? <QD>[]).toList()
                ..sort((a, b) => _ms(b.data()['createdAt'])
                    .compareTo(_ms(a.data()['createdAt'])));

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: isMe ? _changePhoto : null,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundImage: photo.isNotEmpty
                                    ? MemoryImage(_decode(
                                        'ph_${widget.uid}${photo.length}',
                                        photo))
                                    : null,
                                child: photo.isEmpty
                                    ? Text(
                                        username.isEmpty
                                            ? '?'
                                            : username[0].toUpperCase(),
                                        style: const TextStyle(fontSize: 28))
                                    : null,
                              ),
                              if (isMe)
                                const Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: CircleAvatar(
                                    radius: 12,
                                    backgroundColor: Colors.blue,
                                    child: Icon(Icons.camera_alt,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _stat('${docs.length}', 'paylaşım'),
                              _stat('${followers.length}', 'takipçi'),
                              _stat('${following.length}', 'takip'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(username,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          if (bio.isNotEmpty) Text(bio),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: isMe
                        ? SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => _editBio(bio),
                              child: const Text('Biyografiyi düzenle'),
                            ),
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: iFollow
                                    ? OutlinedButton(
                                        onPressed: () => _toggleFollow(true),
                                        child: const Text('Takibi bırak'),
                                      )
                                    : FilledButton(
                                        onPressed: () => _toggleFollow(false),
                                        child: const Text('Takip et'),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.tonal(
                                  onPressed: () => _push(
                                    context,
                                    ChatPage(
                                        otherUid: widget.uid,
                                        otherName: username),
                                  ),
                                  child: const Text('Mesaj'),
                                ),
                              ),
                            ],
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
                                    mainAxisSpacing: 2),
                            itemCount: docs.length,
                            itemBuilder: (c, i) {
                              final img =
                                  (docs[i].data()['image'] ?? '') as String;
                              if (img.isEmpty) return const SizedBox();
                              return GestureDetector(
                                onTap: () => _push(
                                    context, PostDetailPage(id: docs[i].id)),
                                child: Image.memory(_decode(docs[i].id, img),
                                    fit: BoxFit.cover, gaplessPlayback: true),
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

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  late final Stream<QS> _stream =
      _db.collection('chats').where('users', arrayContains: _uid).snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mesajlar')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _push(context, const UserSearchPage()),
        child: const Icon(Icons.edit),
      ),
      body: StreamBuilder<QS>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Hata: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs.toList()
            ..sort((a, b) => _ms(b.data()['lastTime'])
                .compareTo(_ms(a.data()['lastTime'])));
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
                leading: UserAvatar(uid: otherUid, name: otherName, radius: 22),
                title: Text(otherName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text((d['lastMessage'] ?? '') as String,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _push(
                    context, ChatPage(otherUid: otherUid, otherName: otherName)),
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
  late final Stream<QS> _users = _db.collection('users').limit(200).snapshots();

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
      body: StreamBuilder<QS>(
        stream: _users,
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
                leading: UserAvatar(uid: docs[i].id, name: name),
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

  late final Stream<QS> _stream = _db
      .collection('chats')
      .doc(_chatId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots();

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
      if (mounted) _snack(context, 'Gönderilemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(uid: widget.otherUid, name: widget.otherName),
            const SizedBox(width: 12),
            Text(widget.otherName),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QS>(
              stream: _stream,
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text('Henüz mesaj yok'));
                }
                final docs = snap.data!.docs;
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (c, i) {
                    final m = docs[i].data();
                    final mine = m['from'] == _uid;
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
