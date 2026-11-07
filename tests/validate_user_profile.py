"""Validate profile structure and references to the content bundle."""
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker


def main():
    if len(sys.argv) != 4:
        raise SystemExit('usage: validate_user_profile.py PROFILE_SCHEMA.json PROFILE.json CONTENT_FILE.json')
    schema, profile, content = (json.loads(Path(p).read_text()) for p in sys.argv[1:])
    errors = [f'{list(error.absolute_path)}: {error.message}' for error in Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(profile)]
    entries = content if isinstance(content, list) else []
    lemma_ids = {entry['lemma']['id'] for entry in entries}
    senses = {sense['id']: entry['lemma']['id'] for entry in entries for sense in entry['senses']}
    folders = {folder['folder_id']: folder for folder in profile.get('folders', [])}
    if len(folders) != len(profile.get('folders', [])): errors.append('folder_id values must be unique')
    for folder in folders.values():
        parent = folder.get('parent_folder_id')
        if parent is not None and parent not in folders: errors.append(f"{folder['folder_id']}: missing parent folder {parent}")
        seen = {folder['folder_id']}
        while parent is not None and parent in folders:
            if parent in seen:
                errors.append(f"{folder['folder_id']}: folder hierarchy contains a cycle")
                break
            seen.add(parent)
            parent = folders[parent].get('parent_folder_id')

    word_states = profile.get('word_states', [])
    state_ids = [state.get('sense_id') for state in word_states]
    if len(state_ids) != len(set(state_ids)): errors.append('word_states must contain at most one record per sense_id')
    for state in word_states:
        sense_id, lemma_id = state.get('sense_id'), state.get('lemma_id')
        if sense_id not in senses: errors.append(f'{sense_id}: sense does not exist in content')
        elif senses[sense_id] != lemma_id: errors.append(f'{sense_id}: lemma_id does not own this sense')
        for folder_id in state.get('saved_in_folder_ids', []):
            if folder_id not in folders: errors.append(f'{sense_id}: unknown folder {folder_id}')
        progress = state.get('progress', {})
        if progress and progress.get('attempts') != progress.get('correct', 0) + progress.get('incorrect', 0):
            errors.append(f'{sense_id}: attempts must equal correct + incorrect')

    activity_days = profile.get('activity_days', [])
    dates = [day.get('date') for day in activity_days]
    if len(dates) != len(set(dates)): errors.append('activity_days must have one record per local date')
    for day in activity_days:
        if day.get('correct_count', 0) + day.get('incorrect_count', 0) > day.get('practice_count', 0):
            errors.append(f"{day.get('date')}: answer counts exceed practice_count")
        for sense_id in day.get('unique_sense_ids', []):
            if sense_id not in senses: errors.append(f"{day.get('date')}: unknown sense_id {sense_id}")

    snapshot = profile.get('stats_snapshot')
    if snapshot:
        saved = [state for state in word_states if state.get('saved_at') or state.get('saved_in_folder_ids')]
        favorites = [state for state in word_states if state.get('favorite')]
        quiz = [state for state in word_states if state.get('quiz', {}).get('enabled')]
        comparisons = {
            'saved_lemma_count': len({state.get('lemma_id') for state in saved}),
            'saved_sense_count': len(saved),
            'favorite_lemma_count': len({state.get('lemma_id') for state in favorites}),
            'favorite_sense_count': len(favorites),
            'quiz_lemma_count': len({state.get('lemma_id') for state in quiz}),
            'quiz_sense_count': len(quiz),
            'total_active_days': len(activity_days),
            'unique_senses_practiced': len({sid for day in activity_days for sid in day.get('unique_sense_ids', [])}),
            'total_practice_count': sum(day.get('practice_count', 0) for day in activity_days),
            'total_correct_count': sum(day.get('correct_count', 0) for day in activity_days),
            'total_incorrect_count': sum(day.get('incorrect_count', 0) for day in activity_days),
        }
        for key, expected in comparisons.items():
            if snapshot.get(key) != expected: errors.append(f'stats_snapshot.{key} is {snapshot.get(key)}; expected {expected}')

    if errors:
        print('INVALID USER PROFILE')
        print('\n'.join(errors))
        raise SystemExit(1)
    print(f"VALID user profile: {len(folders)} folders, {len(word_states)} word states, {len(activity_days)} activity days")


if __name__ == '__main__':
    main()
