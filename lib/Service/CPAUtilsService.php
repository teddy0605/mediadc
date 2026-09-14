<?php

declare(strict_types=1);

namespace OCA\MediaDC\Service;

use OCA\MediaDC\AppInfo\Application;
use OCA\MediaDC\Db\SettingMapper;
use OCP\App\IAppManager;
use OCP\IConfig;

class CPAUtilsService {
	public function __construct(
		private readonly IConfig $config,
		private readonly SettingMapper $settingMapper,
		private readonly IAppManager $appManager,
		private readonly AppDataService $appDataService,
	) {
	}

	public function getBinaryName(): string {
		$machine = php_uname('m');
		$arch = match ($machine) {
			'x86_64' => 'amd64',
			'aarch64' => 'arm64',
			default => throw new \RuntimeException('Unknown machine type: ' . $machine),
		};
		return 'manylinux_' . $arch;
	}

	public function getPhpInterpreter(): string {
		$basename = basename(PHP_BINARY);
		if ($basename === 'php' || preg_match('/^php\d+(?:\.\d+)*$/', $basename)) {
			return PHP_BINARY;
		}
		// In FPM/CGI context, PHP_BINARY is php-fpm8.3 — find the real CLI
		$candidates = [
			'php' . PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION,
			'php' . PHP_MAJOR_VERSION,
			'php',
		];
		foreach ($candidates as $candidate) {
			$which = trim(shell_exec('which ' . escapeshellarg($candidate) . ' 2>/dev/null') ?: '');
			if ($which !== '' && is_executable($which)) {
				return $which;
			}
		}
		return 'php';
	}

	public function isSnapEnv(): bool {
		return false;
	}

	public function getNCLogLevel(): string {
		$loglevel = $this->config->getSystemValue('loglevel', 2);
		$loglevels = [
			0 => 'DEBUG',
			1 => 'INFO',
			2 => 'WARNING',
			3 => 'ERROR',
			4 => 'FATAL',
		];
		return $loglevels[$loglevel] ?? 'WARNING';
	}

	public function getCpaLogLevel(): string {
		try {
			$setting = $this->settingMapper->findByName('cpa_loglevel');
			return json_decode($setting->getValue());
		} catch (\Exception) {
			return 'WARNING';
		}
	}

	public function isFunctionEnabled(string $functionName): bool {
		if (!function_exists($functionName)) {
			return false;
		}
		$disabled = explode(',', ini_get('disable_functions') ?: '');
		$disabled = array_map('trim', $disabled);
		return !in_array($functionName, $disabled, true);
	}

	public function getSystemInfo(?string $appId = null): array {
		$appVersions = [
			Application::APP_ID . '-version' =>
				$this->appManager->getAppVersion(Application::APP_ID),
		];
		if ($appId !== null) {
			$appVersions[$appId . '-version'] = $this->appManager->getAppVersion($appId);
		}

		return [
			'nextcloud-version' => $this->config->getSystemValue('version'),
			'app-versions' => $appVersions,
			'is-snap' => $this->isSnapEnv(),
			'arch' => php_uname('m'),
			'php-version' => phpversion(),
			'php-interpreter' => $this->getPhpInterpreter(),
			'os' => php_uname('s'),
			'os-release' => php_uname('r'),
			'machine-type' => php_uname('m'),
		];
	}

	/**
	 * Simplified: in source mode we don't need prefetched binaries.
	 * Returns a basic temp path for the app.
	 */
	public function prefetchAppDataFile(string $appId, string $folderName, string $fileName): array|false {
		$tempFolder = sys_get_temp_dir() . '/' . $appId . '/' . $folderName;
		if (!file_exists($tempFolder)) {
			@mkdir($tempFolder, 0700, true);
		}
		return ['success' => true, 'path' => $tempFolder . '/'];
	}

	/**
	 * Simplified: in source mode we skip binary downloads.
	 * Always reports as already downloaded.
	 */
	public function downloadPythonBinaryDir(
		string $url,
		array $binariesFolder,
		string $appId,
		string $filename = 'main',
		bool $update = false,
	): array {
		// Source mode — no binary downloads needed
		return ['downloaded' => true, 'unpacked' => true];
	}
}
