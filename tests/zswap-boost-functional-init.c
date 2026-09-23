#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/fs.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define PAGE_SIZE_BYTES 4096
#define SWAP_HEADER_OFFSET 1024
#define SWAP_MAGIC_OFFSET (PAGE_SIZE_BYTES - 10)
#define TEST_BYTES (64UL * 1024UL * 1024UL)
#define TEST_PAGES (TEST_BYTES / PAGE_SIZE_BYTES)

static void power_off(void)
{
	sync();
	reboot(RB_POWER_OFF);
	for (;;)
		pause();
}

static void fail_errno(const char *step)
{
	int saved_errno = errno;

	printf("FUNCTIONAL:FAIL:%s:%s\n", step, strerror(saved_errno));
	fflush(stdout);
	power_off();
}

static void fail_message(const char *step)
{
	printf("FUNCTIONAL:FAIL:%s\n", step);
	fflush(stdout);
	power_off();
}

static void mount_if_needed(const char *source, const char *target,
			    const char *filesystem)
{
	if (mount(source, target, filesystem, 0, NULL) && errno != EBUSY)
		fail_errno(target);
}

static void write_text(const char *path, const char *text)
{
	int fd = open(path, O_WRONLY | O_CLOEXEC);
	size_t length = strlen(text);

	if (fd < 0)
		fail_errno(path);
	if (write(fd, text, length) != (ssize_t)length)
		fail_errno(path);
	close(fd);
}

static void format_swap(const char *device)
{
	uint64_t bytes;
	uint64_t pages;
	uint32_t version = 1;
	uint32_t last_page;
	uint32_t bad_pages = 0;
	unsigned char header[PAGE_SIZE_BYTES] = {0};
	int fd = open(device, O_RDWR | O_CLOEXEC);

	if (fd < 0)
		fail_errno("open-swap-device");
	if (ioctl(fd, BLKGETSIZE64, &bytes))
		fail_errno("swap-device-size");
	pages = bytes / PAGE_SIZE_BYTES;
	if (pages < 2 || pages - 1 > UINT32_MAX) {
		errno = EINVAL;
		fail_errno("swap-device-pages");
	}
	last_page = (uint32_t)(pages - 1);
	memcpy(header + SWAP_HEADER_OFFSET, &version, sizeof(version));
	memcpy(header + SWAP_HEADER_OFFSET + sizeof(version), &last_page,
	       sizeof(last_page));
	memcpy(header + SWAP_HEADER_OFFSET + 2 * sizeof(version), &bad_pages,
	       sizeof(bad_pages));
	memcpy(header + SWAP_MAGIC_OFFSET, "SWAPSPACE2", 10);
	if (pwrite(fd, header, sizeof(header), 0) != (ssize_t)sizeof(header))
		fail_errno("write-swap-header");
	if (fsync(fd))
		fail_errno("sync-swap-header");
	close(fd);
}

static void wait_for_swap_device(void)
{
	struct timespec pause_time = { .tv_sec = 0, .tv_nsec = 100000000 };
	int retries;

	for (retries = 0; retries < 50; retries++) {
		if (!access("/dev/vda", R_OK | W_OK))
			return;
		nanosleep(&pause_time, NULL);
	}
	errno = ENOENT;
	fail_errno("wait-for-vda");
}

static uint64_t read_counter(const char *path)
{
	char buffer[64];
	char *end;
	ssize_t length;
	uint64_t value;
	int fd = open(path, O_RDONLY | O_CLOEXEC);

	if (fd < 0)
		fail_errno(path);
	length = read(fd, buffer, sizeof(buffer) - 1);
	if (length <= 0)
		fail_errno(path);
	close(fd);
	buffer[length] = '\0';
	errno = 0;
	value = strtoull(buffer, &end, 10);
	if (errno || end == buffer || (*end != '\n' && *end != '\0'))
		fail_message("invalid-debugfs-counter");
	return value;
}

static unsigned char pattern(size_t page, size_t offset)
{
	return (unsigned char)((page * 17U + (offset / 64U) * 29U +
				(offset & 7U)) & 0xffU);
}

static void fill_pages(unsigned char *memory)
{
	size_t page;
	size_t offset;

	for (page = 0; page < TEST_PAGES; page++) {
		for (offset = 0; offset < PAGE_SIZE_BYTES; offset++)
			memory[page * PAGE_SIZE_BYTES + offset] = pattern(page, offset);
	}
}

static void verify_pages(const unsigned char *memory)
{
	size_t page;
	size_t offset;

	for (page = 0; page < TEST_PAGES; page++) {
		for (offset = 0; offset < PAGE_SIZE_BYTES; offset++) {
			if (memory[page * PAGE_SIZE_BYTES + offset] !=
			    pattern(page, offset))
				fail_message("data-mismatch");
		}
	}
}

int main(void)
{
	const char *compress_path =
		"/sys/kernel/debug/zswap_boost/full_compress";
	const char *decompress_path =
		"/sys/kernel/debug/zswap_boost/full_decompress";
	unsigned char *memory;
	uint64_t compress_before;
	uint64_t compress_after;
	uint64_t decompress_before;
	uint64_t decompress_after;

	mkdir("/proc", 0555);
	mkdir("/sys", 0555);
	mkdir("/dev", 0755);
	mkdir("/sys/kernel", 0555);
	mkdir("/sys/kernel/debug", 0555);
	mount_if_needed("proc", "/proc", "proc");
	mount_if_needed("sysfs", "/sys", "sysfs");
	mount_if_needed("devtmpfs", "/dev", "devtmpfs");
	mount_if_needed("debugfs", "/sys/kernel/debug", "debugfs");
	printf("FUNCTIONAL:BOOTED\n");
	fflush(stdout);

	write_text("/proc/sys/vm/enable_zswap_switch", "1\n");
	printf("FUNCTIONAL:BOOST_ENABLED\n");
	fflush(stdout);
	if (access(compress_path, R_OK) || access(decompress_path, R_OK))
		fail_errno("zswap-boost-debugfs");
	printf("FUNCTIONAL:DEBUGFS_READY\n");
	fflush(stdout);

	wait_for_swap_device();
	format_swap("/dev/vda");
	if (syscall(SYS_swapon, "/dev/vda", 0))
		fail_errno("swapon");
	printf("FUNCTIONAL:SWAP_ENABLED\n");
	fflush(stdout);

	memory = mmap(NULL, TEST_BYTES, PROT_READ | PROT_WRITE,
		      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (memory == MAP_FAILED)
		fail_errno("mmap");
	if (madvise(memory, TEST_BYTES, MADV_NOHUGEPAGE))
		fail_errno("madvise-nohugepage");
	fill_pages(memory);

	compress_before = read_counter(compress_path);
	decompress_before = read_counter(decompress_path);
	if (madvise(memory, TEST_BYTES, MADV_PAGEOUT))
		fail_errno("madvise-pageout");
	compress_after = read_counter(compress_path);
	if (compress_after <= compress_before)
		fail_message("compress-counter-not-incremented");
	printf("FUNCTIONAL:COMPRESS_DELTA:%" PRIu64 "\n",
	       compress_after - compress_before);
	fflush(stdout);

	verify_pages(memory);
	decompress_after = read_counter(decompress_path);
	if (decompress_after <= decompress_before)
		fail_message("decompress-counter-not-incremented");
	printf("FUNCTIONAL:DECOMPRESS_DELTA:%" PRIu64 "\n",
	       decompress_after - decompress_before);
	printf("FUNCTIONAL:DATA_VERIFIED:%lu\n", (unsigned long)TEST_PAGES);
	fflush(stdout);

	if (munmap(memory, TEST_BYTES))
		fail_errno("munmap");
	if (syscall(SYS_swapoff, "/dev/vda"))
		fail_errno("swapoff");
	printf("FUNCTIONAL:PASS\n");
	fflush(stdout);
	power_off();
}
