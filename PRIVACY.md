# Afterimage Privacy Policy

Effective date: July 12, 2026

Afterimage is designed without accounts, advertising, analytics, or an Afterimage-operated backend. This policy describes how the app handles photos, location, camera access, and network requests.

## Information processed on your device

Afterimage may process the following information locally when you choose a feature that needs it:

- a photo you capture in the app;
- a photo you select from your Photos library;
- location metadata associated with a selected photo;
- a location you choose on the map;
- your current location and, when available, compass heading.

This information is used to search and rank historical photographs near a place. Afterimage does not upload your photo, precise location, or compass heading to an Afterimage server.

## Historical-image requests

The app includes a local metadata index, but historical image files are hosted by source archives. To display an uncached image, Afterimage requests it over HTTPS from the host identified by the record, currently New York Public Library image infrastructure (`images.nypl.org`) or Wikimedia Commons (`upload.wikimedia.org`).

Like ordinary web requests, those archive hosts may receive network information such as your IP address, request time, device/network headers, and the URL of the requested image. Their handling of that information is governed by their own privacy policies. Afterimage does not send your captured photo or precise device location with an image request.

## Local storage

The app bundles a read-only historical-photo metadata database. Downloaded historical images may be cached on the device to improve performance and are configured to expire after 30 days, subject to operating-system cache management. The app does not maintain a user account or cloud profile.

You can remove the app and its local cache through iOS. You can also manage Camera, Photos, and Location permissions in iOS Settings.

## Data collection, tracking, and sharing

Afterimage does not include an analytics SDK, advertising SDK, or tracking technology. It does not sell personal information. It does not collect information into an Afterimage-controlled database.

Requests made directly to historical-image hosts are necessary to provide the image-display feature and are described above. The app also uses Apple system frameworks and the network services provided by your device and operating system.

## Children

Afterimage is not designed to collect personal information from children or any other user. If the product's data practices change, this policy and the App Store privacy disclosures must be updated before the changed version is distributed.

## Changes to this policy

Material changes will be published at this URL with a new effective date. App Store disclosures will be updated when required.

## Contact

Privacy questions can be raised through the public support repository:

https://github.com/saagpatel/Afterimage/issues
