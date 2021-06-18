from json import loads, dumps

from datetime import datetime, timedelta

from copy import deepcopy

interpolated = []

with open('data.json', 'r') as f:
	data = loads(f.read())

changed = True
once_flag = False

new_timestamps = []

while once_flag is False or changed is True:
	once_flag = True
	changed = False

	data['features'].sort(key=lambda x: x['properties']['observed'])

	prev_timestamp = None
	prev_data = None

	for feature in data['features']:
		timestamp = feature['properties']['observed']
		temperature = feature['properties']['value']
		parsed_time = datetime.strptime(timestamp, '%Y-%m-%dT%H:%M:%SZ')

		if prev_timestamp is not None:
			expected_time = prev_timestamp + timedelta(hours=1)

			if parsed_time != expected_time:
				changed = True
				new_time = expected_time.strftime('%Y-%m-%dT%H:%M:%SZ')
				new_timestamps.append(new_time)
				new_data = deepcopy(prev_data)
				new_data['properties']['observed'] = new_time
				# new_data['properties']['value'] = -99.9
				data['features'].append(new_data)
				break

		prev_timestamp = parsed_time
		prev_data = deepcopy(feature)

new_timestamps.sort()

with open('datafixed.json', 'w') as f:
	f.write(dumps(data, indent=4))

print(f'New Timestamps ({len(new_timestamps)})')
for new_time in new_timestamps:
	print(f'\t{new_time}')