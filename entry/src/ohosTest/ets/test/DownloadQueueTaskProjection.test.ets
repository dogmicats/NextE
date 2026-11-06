import { describe, expect, it } from '@ohos/hypium'
import { DownloadQueueTaskProjection } from 'download'
import {
  DownloadArchiverTask,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
  DownloadSortMode,
} from 'shared'

function galleryTask(
  gid: string,
  title: string,
  status: string,
  queuedAt: number,
): DownloadGalleryTask {
  const task: DownloadGalleryTask = new DownloadGalleryTask()
  task.gid = gid
  task.token = `token-${gid}`
  task.title = title
  task.status = status
  task.queuedAt = queuedAt
  return task
}

function archiverTask(
  tag: string,
  title: string,
  status: string,
  queuedAt: number,
): DownloadArchiverTask {
  const task: DownloadArchiverTask = new DownloadArchiverTask()
  task.tag = tag
  task.gid = `gid-${tag}`
  task.title = title
  task.status = status
  task.queuedAt = queuedAt
  return task
}

function seedWithBytes(bytes: number): DownloadImageSeed {
  const seed: DownloadImageSeed = new DownloadImageSeed()
  seed.bytesWritten = bytes
  return seed
}

export default function downloadQueueTaskProjectionTest(): void {
  describe('DownloadQueueTaskProjection', () => {
    it('keeps the existing status groups and live task references while ordering each group once', 0, (done: Function) => {
      const alpha: DownloadGalleryTask = galleryTask('alpha', 'Alpha', DownloadGalleryTaskStatus.QUEUED, 20)
      const zulu: DownloadGalleryTask = galleryTask('zulu', 'Zulu', DownloadGalleryTaskStatus.DOWNLOADING, 30)
      const partial: DownloadGalleryTask = galleryTask('partial', 'Half', DownloadGalleryTaskStatus.COMPLETE, 25)
      partial.pageCount = 4
      partial.downloadedFiles = 2
      const paused: DownloadGalleryTask = galleryTask('paused', 'Paused', DownloadGalleryTaskStatus.PAUSED, 15)
      const failed: DownloadGalleryTask = galleryTask('failed', 'Failed', DownloadGalleryTaskStatus.ERROR, 10)
      const complete: DownloadGalleryTask = galleryTask('complete', 'Done', DownloadGalleryTaskStatus.COMPLETE, 5)
      complete.pageCount = 2
      complete.downloadedFiles = 2

      const archiverActive: DownloadArchiverTask = archiverTask('active', 'Archive Active', DownloadGalleryTaskStatus.QUEUED, 20)
      const archiverPaused: DownloadArchiverTask = archiverTask('paused', 'Archive Paused', DownloadGalleryTaskStatus.PAUSED, 15)
      const archiverFailed: DownloadArchiverTask = archiverTask('failed', 'Archive Failed', DownloadGalleryTaskStatus.ERROR, 10)
      const archiverComplete: DownloadArchiverTask = archiverTask('complete', 'Archive Done', DownloadGalleryTaskStatus.COMPLETE, 5)

      const projection: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [zulu, paused, partial, complete, alpha, failed],
        [archiverComplete, archiverFailed, archiverPaused, archiverActive],
        '',
        DownloadSortMode.TITLE_ASC,
      )

      expect(projection.galleryVisibleCount).assertEqual(6)
      expect(projection.archiverVisibleCount).assertEqual(4)
      expect(projection.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('alpha,partial,zulu')
      expect(projection.galleryTasksForGroup(1)[0].gid).assertEqual('paused')
      expect(projection.galleryTasksForGroup(2)[0].gid).assertEqual('failed')
      expect(projection.galleryTasksForGroup(3)[0].gid).assertEqual('complete')
      expect(projection.archiverTasksForGroup(0)[0].tag).assertEqual('active')
      expect(projection.archiverTasksForGroup(1)[0].tag).assertEqual('paused')
      expect(projection.archiverTasksForGroup(2)[0].tag).assertEqual('failed')
      expect(projection.archiverTasksForGroup(3)[0].tag).assertEqual('complete')

      alpha.activeBytesWritten = 1024
      expect(projection.galleryTasksForGroup(0)[0].activeBytesWritten).assertEqual(1024)
      expect(projection.galleryTasksForGroup(-1).length).assertEqual(0)
      expect(projection.archiverTasksForGroup(4).length).assertEqual(0)
      done()
    })

    it('preserves every sort mode and the existing searchable fields', 0, (done: Function) => {
      const alpha: DownloadGalleryTask = galleryTask('alpha', 'Zulu', DownloadGalleryTaskStatus.QUEUED, 10)
      alpha.category = 'Category Needle'
      const beta: DownloadGalleryTask = galleryTask('beta', 'Alpha', DownloadGalleryTaskStatus.QUEUED, 20)
      const archiver: DownloadArchiverTask = archiverTask('archive', 'Archive', DownloadGalleryTaskStatus.QUEUED, 30)
      archiver.fileName = 'target-file.cbz'

      const addedAsc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [beta, alpha],
        [],
        '',
        DownloadSortMode.ADDED_ASC,
      )
      const addedDesc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [beta, alpha],
        [],
        '',
        DownloadSortMode.ADDED_DESC,
      )
      const titleAsc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [alpha, beta],
        [],
        '',
        DownloadSortMode.TITLE_ASC,
      )
      const titleDesc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [alpha, beta],
        [],
        '',
        DownloadSortMode.TITLE_DESC,
      )
      const gallerySearch: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [alpha, beta],
        [archiver],
        '  category needle  ',
        DownloadSortMode.ADDED_DESC,
      )
      const archiverSearch: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [alpha, beta],
        [archiver],
        'TARGET-FILE',
        DownloadSortMode.ADDED_DESC,
      )

      expect(addedAsc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('alpha,beta')
      expect(addedDesc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('beta,alpha')
      expect(titleAsc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('beta,alpha')
      expect(titleDesc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('alpha,beta')
      expect(gallerySearch.galleryVisibleCount).assertEqual(1)
      expect(gallerySearch.galleryTasksForGroup(0)[0].gid).assertEqual('alpha')
      expect(gallerySearch.archiverVisibleCount).assertEqual(0)
      expect(archiverSearch.galleryVisibleCount).assertEqual(0)
      expect(archiverSearch.archiverVisibleCount).assertEqual(1)
      expect(archiverSearch.archiverTasksForGroup(0)[0].tag).assertEqual('archive')
      done()
    })

    it('orders publish-time sorts with an added-time fallback for tasks without publish time', 0, (done: Function) => {
      const oldPosted: DownloadGalleryTask = galleryTask('old-posted', 'Old Posted', DownloadGalleryTaskStatus.QUEUED, 50)
      oldPosted.postedAt = 1000
      const newPosted: DownloadGalleryTask = galleryTask('new-posted', 'New Posted', DownloadGalleryTaskStatus.QUEUED, 60)
      newPosted.postedAt = 4000
      const legacy: DownloadGalleryTask = galleryTask('legacy', 'Legacy', DownloadGalleryTaskStatus.QUEUED, 2000)

      const postedDesc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [legacy, oldPosted, newPosted],
        [],
        '',
        DownloadSortMode.POSTED_DESC,
      )
      const postedAsc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [legacy, oldPosted, newPosted],
        [],
        '',
        DownloadSortMode.POSTED_ASC,
      )

      expect(postedDesc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('new-posted,legacy,old-posted')
      expect(postedAsc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('old-posted,legacy,new-posted')

      const archiverOld: DownloadArchiverTask = archiverTask('arch-old', 'Archive Old', DownloadGalleryTaskStatus.QUEUED, 70)
      archiverOld.postedAt = 1200
      const archiverNew: DownloadArchiverTask = archiverTask('arch-new', 'Archive New', DownloadGalleryTaskStatus.QUEUED, 80)
      archiverNew.postedAt = 4200
      const archiverPostedDesc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [],
        [archiverOld, archiverNew],
        '',
        DownloadSortMode.POSTED_DESC,
      )
      const archiverPostedAsc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [],
        [archiverOld, archiverNew],
        '',
        DownloadSortMode.POSTED_ASC,
      )

      expect(archiverPostedDesc.archiverTasksForGroup(0).map((task: DownloadArchiverTask): string => task.tag).join(','))
        .assertEqual('arch-new,arch-old')
      expect(archiverPostedAsc.archiverTasksForGroup(0).map((task: DownloadArchiverTask): string => task.tag).join(','))
        .assertEqual('arch-old,arch-new')
      done()
    })

    it('orders size sorts by persisted bytes with an added-time tie-break', 0, (done: Function) => {
      const small: DownloadGalleryTask = galleryTask('small', 'Small', DownloadGalleryTaskStatus.QUEUED, 10)
      small.imageSeeds = [seedWithBytes(100), seedWithBytes(200)]
      const large: DownloadGalleryTask = galleryTask('large', 'Large', DownloadGalleryTaskStatus.QUEUED, 20)
      large.imageSeeds = [seedWithBytes(900), seedWithBytes(800)]
      const sameOlder: DownloadGalleryTask = galleryTask('same-older', 'Same Older', DownloadGalleryTaskStatus.QUEUED, 30)
      sameOlder.imageSeeds = [seedWithBytes(500)]
      const sameNewer: DownloadGalleryTask = galleryTask('same-newer', 'Same Newer', DownloadGalleryTaskStatus.QUEUED, 40)
      sameNewer.imageSeeds = [seedWithBytes(500)]

      const sizeDesc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [small, sameNewer, large, sameOlder],
        [],
        '',
        DownloadSortMode.SIZE_DESC,
      )
      const sizeAsc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [small, sameNewer, large, sameOlder],
        [],
        '',
        DownloadSortMode.SIZE_ASC,
      )

      expect(sizeDesc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('large,same-newer,same-older,small')
      expect(sizeAsc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('small,same-newer,same-older,large')

      const archiverSmall: DownloadArchiverTask = archiverTask('arch-small', 'Archive Small', DownloadGalleryTaskStatus.QUEUED, 90)
      archiverSmall.bytesWritten = 250
      const archiverLarge: DownloadArchiverTask = archiverTask('arch-large', 'Archive Large', DownloadGalleryTaskStatus.QUEUED, 95)
      archiverLarge.bytesWritten = 950
      const archiverSizeDesc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [],
        [archiverSmall, archiverLarge],
        '',
        DownloadSortMode.SIZE_DESC,
      )
      const archiverSizeAsc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [],
        [archiverSmall, archiverLarge],
        '',
        DownloadSortMode.SIZE_ASC,
      )

      expect(archiverSizeDesc.archiverTasksForGroup(0).map((task: DownloadArchiverTask): string => task.tag).join(','))
        .assertEqual('arch-large,arch-small')
      expect(archiverSizeAsc.archiverTasksForGroup(0).map((task: DownloadArchiverTask): string => task.tag).join(','))
        .assertEqual('arch-small,arch-large')
      done()
    })
  })
}
