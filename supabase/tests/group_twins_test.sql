-- Jumelage d'un cercle avec un groupe d'une autre app (Agora, Arpente) et
-- demandes d'adhésion par le code d'un jumeau : droits, formats, code réservé
-- au créateur, blocages, plafond d'essais, défaire, cascades.
-- Jouer : supabase test db (pile locale démarrée).
begin;
create extension if not exists pgtap with schema extensions;
select plan(49);

-- Cléo crée le cercle ; Max (ami) en est membre. Ines et Zoé sont des inconnues,
-- Bob est bloqué par Cléo, Lou a bloqué le cercle, Pat essaie des codes au hasard.
insert into auth.users (id, email) values
  ('c1000000-0000-0000-0000-0000000000c1', 'cleo@test.local'),
  ('c2000000-0000-0000-0000-0000000000c2', 'max@test.local'),
  ('c3000000-0000-0000-0000-0000000000c3', 'ines@test.local'),
  ('c4000000-0000-0000-0000-0000000000c4', 'bob@test.local'),
  ('c5000000-0000-0000-0000-0000000000c5', 'lou@test.local'),
  ('c6000000-0000-0000-0000-0000000000c6', 'zoe@test.local'),
  ('c7000000-0000-0000-0000-0000000000c7', 'pat@test.local');
update public.profiles set handle = 'cleo' where id = 'c1000000-0000-0000-0000-0000000000c1';
update public.profiles set handle = 'max'  where id = 'c2000000-0000-0000-0000-0000000000c2';

insert into public.groups (id, name, creator_id) values
  ('9a000000-0000-0000-0000-00000000009a', 'Les copains', 'c1000000-0000-0000-0000-0000000000c1');
insert into public.group_members (group_id, user_id) values
  ('9a000000-0000-0000-0000-00000000009a', 'c1000000-0000-0000-0000-0000000000c1'),
  ('9a000000-0000-0000-0000-00000000009a', 'c2000000-0000-0000-0000-0000000000c2');
insert into public.blocks (blocker_id, blocked_id) values
  ('c1000000-0000-0000-0000-0000000000c1', 'c4000000-0000-0000-0000-0000000000c4');
insert into public.group_blocks (user_id, group_id) values
  ('c5000000-0000-0000-0000-0000000000c5', '9a000000-0000-0000-0000-00000000009a');

-- Droits de base ---------------------------------------------------------------------------
select ok(not has_table_privilege('anon', 'public.group_twins', 'select'),
  'anon ne lit pas les jumeaux');
select ok(not has_table_privilege('authenticated', 'public.group_twins', 'insert')
  and not has_table_privilege('authenticated', 'public.group_twins', 'update')
  and not has_table_privilege('authenticated', 'public.group_twins', 'truncate'),
  'authenticated n''écrit les jumeaux que par twin_group');
select ok(not has_column_privilege('authenticated', 'public.group_twins', 'code', 'select'),
  'le code donné au jumeau n''est pas lisible par colonne');
select ok(not has_table_privilege('authenticated', 'public.group_join_requests', 'insert')
  and not has_table_privilege('authenticated', 'public.group_join_requests', 'truncate'),
  'une demande ne s''écrit que par request_to_join');
select ok(not has_function_privilege('anon', 'public.twin_group(uuid, text, text)', 'execute')
  and not has_function_privilege('anon', 'public.request_to_join(text)', 'execute')
  and not has_function_privilege('anon', 'public.join_code_preview(text)', 'execute'),
  'anon n''appelle aucune RPC de jumelage');
select ok(not has_function_privilege('authenticated', 'private.random_join_code()', 'execute'),
  'les helpers de code restent privés');

-- Qui peut jumeler ------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"c2000000-0000-0000-0000-0000000000c2","role":"authenticated"}';
select throws_ok(
  $$select public.twin_group('9a000000-0000-0000-0000-00000000009a', 'agora')$$,
  '42501', 'not_group_creator', 'un membre ne jumelle pas le cercle');

-- Cléo lance le jumelage avec Agora : jumeau en attente ----------------------------------
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select set_config('dd_test.agora', public.twin_group('9a000000-0000-0000-0000-00000000009a', 'agora'), true);
select matches(current_setting('dd_test.agora'), '^[A-HJ-NP-Z2-9]{8}$',
  'le jumelage rend un code de 8 caractères');
select ok(
  (select remote_code is null from public.group_twins
   where group_id = '9a000000-0000-0000-0000-00000000009a' and app = 'agora'),
  'lancé d''ici, le jumeau attend le code du groupe Agora');
select is(public.twin_group('9a000000-0000-0000-0000-00000000009a', 'agora'),
  current_setting('dd_test.agora'), 'relancer reprend le même code');
select throws_ok(
  $$select public.twin_group('9a000000-0000-0000-0000-00000000009a', 'deckhand')$$,
  '22023', 'invalid_twin_app', 'une app hors liste est refusée');
select throws_ok(
  $$select public.twin_group('9a000000-0000-0000-0000-00000000009a', 'agora', 'ABC234')$$,
  '22023', 'invalid_twin_code', 'un code Agora doit avoir 8 caractères');

-- La réponse d'Agora complète le jumeau ----------------------------------------------------
select is(public.twin_group('9a000000-0000-0000-0000-00000000009a', 'agora', ' abcd2345 '),
  current_setting('dd_test.agora'), 'compléter garde le code du cercle');
select is(
  (select remote_code from public.group_twins
   where group_id = '9a000000-0000-0000-0000-00000000009a' and app = 'agora'),
  'ABCD2345', 'le code Agora est rangé en majuscules, sans espaces');
select is(public.twin_group('9a000000-0000-0000-0000-00000000009a', 'agora', 'ABCD2345'),
  current_setting('dd_test.agora'), 'la même réponse rejouée ne change rien');
select throws_ok(
  $$select public.twin_group('9a000000-0000-0000-0000-00000000009a', 'agora', 'WXYZ6789')$$,
  '23505', 'twin_exists', 'un jumeau complet ne se remplace pas par un lien');

-- Un jumeau Arpente reçu (demande venue d'Arpente) : son propre code -----------------------
select set_config('dd_test.arpente',
  public.twin_group('9a000000-0000-0000-0000-00000000009a', 'arpente', 'qrs789'), true);
select isnt(current_setting('dd_test.arpente'), current_setting('dd_test.agora'),
  'chaque jumeau a son propre code');

-- Qui lit les jumeaux --------------------------------------------------------------------
set local request.jwt.claims = '{"sub":"c2000000-0000-0000-0000-0000000000c2","role":"authenticated"}';
select is(
  (select array_agg(app || ':' || remote_code order by app) from public.group_twins),
  array['agora:ABCD2345', 'arpente:QRS789'], 'un membre voit les deux jumeaux et leurs codes distants');
select throws_ok($$select code from public.group_twins$$, '42501', null,
  'un membre ne lit pas les codes donnés aux jumeaux');
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000000c3","role":"authenticated"}';
select is((select count(*)::int from public.group_twins), 0, 'une inconnue ne voit aucun jumeau');

-- Aperçu et demande d'Ines -----------------------------------------------------------------
select results_eq(
  format($$select name, creator_handle, is_member, already_requested from public.join_code_preview(%L)$$,
    lower(current_setting('dd_test.agora'))),
  $$values ('Les copains'::text, 'cleo'::text, false, false)$$,
  'l''aperçu dit le cercle et son créateur (casse ignorée)');
select is((select count(*)::int from public.join_code_preview('ZZZZ2222')), 0,
  'un code inconnu ne montre rien');
select is(public.request_to_join(current_setting('dd_test.agora')), 'requested', 'Ines demande à entrer');
select is(public.request_to_join(current_setting('dd_test.arpente')), 'already_requested',
  'une seconde demande au même cercle ne s''empile pas');
select is((select already_requested from public.join_code_preview(current_setting('dd_test.agora'))), true,
  'l''aperçu sait que la demande est partie');
select is((select count(*)::int from public.group_join_requests), 1, 'Ines voit sa demande');
select throws_ok(
  $$insert into public.group_join_requests (group_id, user_id)
    values ('9a000000-0000-0000-0000-00000000009a', 'c3000000-0000-0000-0000-0000000000c3')$$,
  '42501', null, 'une demande ne s''insère pas à la main');

set local request.jwt.claims = '{"sub":"c2000000-0000-0000-0000-0000000000c2","role":"authenticated"}';
select is(public.request_to_join(current_setting('dd_test.agora')), 'already_member',
  'un membre n''a rien à demander');
select is((select count(*)::int from public.group_join_requests), 0,
  'un simple membre ne voit pas les demandes');
select throws_ok(
  $$select public.answer_join_request('9a000000-0000-0000-0000-00000000009a',
      'c3000000-0000-0000-0000-0000000000c3', true)$$,
  '42501', 'not_group_creator', 'un simple membre ne tranche pas');

-- Cléo accepte Ines -------------------------------------------------------------------------
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is((select count(*)::int from public.group_join_requests), 1, 'la créatrice voit la demande');
select lives_ok(
  $$select public.answer_join_request('9a000000-0000-0000-0000-00000000009a',
      'c3000000-0000-0000-0000-0000000000c3', true)$$,
  'la créatrice accepte');
select ok(
  exists (select 1 from public.group_members
          where group_id = '9a000000-0000-0000-0000-00000000009a'
            and user_id = 'c3000000-0000-0000-0000-0000000000c3'),
  'Ines est entrée, sans être amie de la créatrice');
select is((select count(*)::int from public.group_join_requests), 0, 'la demande acceptée disparaît');
select throws_ok(
  $$select public.answer_join_request('9a000000-0000-0000-0000-00000000009a',
      'c3000000-0000-0000-0000-0000000000c3', true)$$,
  'P0002', 'request_not_found', 'trancher une demande absente échoue');

-- Blocages : même réponse qu'un code inconnu -----------------------------------------------
set local request.jwt.claims = '{"sub":"c4000000-0000-0000-0000-0000000000c4","role":"authenticated"}';
select is((select count(*)::int from public.join_code_preview(current_setting('dd_test.agora'))), 0,
  'quelqu''un que la créatrice a bloqué ne voit rien');
select is(public.request_to_join(current_setting('dd_test.agora')), 'invalid',
  'ni ne peut demander');
set local request.jwt.claims = '{"sub":"c5000000-0000-0000-0000-0000000000c5","role":"authenticated"}';
select is(public.request_to_join(current_setting('dd_test.agora')), 'invalid',
  'qui a bloqué le cercle ne peut pas demander à y entrer');

-- Refuser, annuler -------------------------------------------------------------------------
set local request.jwt.claims = '{"sub":"c6000000-0000-0000-0000-0000000000c6","role":"authenticated"}';
select is(public.request_to_join(current_setting('dd_test.agora')), 'requested', 'Zoé demande');
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select public.answer_join_request('9a000000-0000-0000-0000-00000000009a',
  'c6000000-0000-0000-0000-0000000000c6', false);
select ok(
  not exists (select 1 from public.group_members
              where group_id = '9a000000-0000-0000-0000-00000000009a'
                and user_id = 'c6000000-0000-0000-0000-0000000000c6')
  and (select count(*) from public.group_join_requests) = 0,
  'refuser retire la demande sans faire entrer');
set local request.jwt.claims = '{"sub":"c6000000-0000-0000-0000-0000000000c6","role":"authenticated"}';
select public.request_to_join(current_setting('dd_test.agora'));
delete from public.group_join_requests where user_id = 'c6000000-0000-0000-0000-0000000000c6';
select is((select count(*)::int from public.group_join_requests), 0, 'Zoé annule sa demande');
select public.request_to_join(current_setting('dd_test.arpente'));

-- Plafond d'essais : vingt codes inconnus en une heure -------------------------------------
set local request.jwt.claims = '{"sub":"c7000000-0000-0000-0000-0000000000c7","role":"authenticated"}';
select is((select count(*)::int from generate_series(1, 20) i
           where public.request_to_join('ZZZZ2222') = 'invalid'), 20,
  'vingt codes inconnus répondent « invalid »');
select throws_ok($$select public.request_to_join('ZZZZ2222')$$, '23514', 'rate_limited',
  'le vingt-et-unième essai est freiné');
select throws_ok(format($$select * from public.join_code_preview(%L)$$, current_setting('dd_test.agora')),
  '23514', 'rate_limited', 'l''aperçu aussi, même pour un bon code');

-- Défaire : le code meurt, l'autre jumeau et les demandes restent --------------------------
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select public.untwin_group('9a000000-0000-0000-0000-00000000009a', 'arpente');
select is((select array_agg(app) from public.group_twins), array['agora'],
  'défaire ne retire que ce jumeau');
select is((select count(*)::int from public.group_join_requests), 1,
  'la demande reçue par ce jumeau reste à trancher');
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000000c3","role":"authenticated"}';
select is(public.request_to_join(current_setting('dd_test.arpente')), 'invalid',
  'le code d''un jumeau défait n''ouvre plus rien');

-- Cascades ---------------------------------------------------------------------------------
reset role;
delete from auth.users where id = 'c7000000-0000-0000-0000-0000000000c7';
select is((select count(*)::int from private.join_code_failures
           where user_id = 'c7000000-0000-0000-0000-0000000000c7'), 0,
  'les essais partent avec le compte');
delete from public.groups where id = '9a000000-0000-0000-0000-00000000009a';
select ok(
  (select count(*) from public.group_twins) = 0
  and (select count(*) from public.group_join_requests) = 0,
  'jumeaux et demandes partent avec le cercle');

select * from finish();
rollback;
