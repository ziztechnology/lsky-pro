<?php

namespace App\Http\Controllers\User;

use App\Enums\AlbumAuthorizationLevel;
use App\Http\Controllers\Controller;
use App\Models\Album;
use App\Models\Image;
use App\Models\User;
use App\Services\UserService;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Auth;

class AlbumAuthorizationController extends Controller
{
    /**
     * 查看相册已授权用户列表（仅相册所有者可调用）
     * GET /user/albums/{id}/authorized-users
     */
    public function authorizedUsers(Request $request): Response
    {
        /** @var User $owner */
        $owner = Auth::user();
        /** @var Album|null $album */
        $album = $owner->albums()->find($request->route('id'));
        if (is_null($album)) {
            return $this->fail('不存在的相册或无权操作');
        }

        $authorizedUsers = $album->authorizedUsers()
            ->select('users.id', 'users.name', 'users.email')
            ->get()
            ->map(function (User $user) {
                $level = AlbumAuthorizationLevel::fromIntSafe((int) $user->pivot->permission_level);
                return [
                    'id'               => $user->id,
                    'name'             => $user->name,
                    'email'            => $user->email,
                    'permission_level' => $level->value,
                    'permission_label' => $level->label(),
                    'abilities'        => $level->abilities(),
                ];
            });

        return $this->success('success', compact('authorizedUsers'));
    }

    /**
     * 授权指定用户访问相册（支持指定权限级别；已授权则更新级别）
     * POST /user/albums/{id}/authorize
     * Body: { email: string, permission_level: 1|2|3 }
     */
    public function authorize(Request $request): Response
    {
        /** @var User $owner */
        $owner = Auth::user();
        /** @var Album|null $album */
        $album = $owner->albums()->find($request->route('id'));
        if (is_null($album)) {
            return $this->fail('不存在的相册或无权操作');
        }

        $email = $request->input('email');
        if (empty($email)) {
            return $this->fail('请输入用户邮箱');
        }

        /** @var User|null $targetUser */
        $targetUser = User::query()->where('email', $email)->first();
        if (is_null($targetUser)) {
            return $this->fail('未找到该邮箱对应的用户');
        }
        if ($targetUser->id === $owner->id) {
            return $this->fail('不能授权给自己');
        }

        // 解析权限级别，不合法时默认只读
        $level = AlbumAuthorizationLevel::fromIntSafe((int) $request->input('permission_level', 1));

        // 已存在授权则更新级别，否则新建
        $existing = $album->authorizedUsers()->where('users.id', $targetUser->id)->first();
        if ($existing) {
            $album->authorizedUsers()->updateExistingPivot($targetUser->id, [
                'permission_level' => $level->value,
            ]);
            $message = "已将 {$targetUser->name} 的权限更新为「{$level->label()}」";
        } else {
            $album->authorizedUsers()->attach($targetUser->id, [
                'permission_level' => $level->value,
            ]);
            $message = "已授权 {$targetUser->name}（{$level->label()}）访问此相册";
        }

        return $this->success($message, [
            'user' => [
                'id'               => $targetUser->id,
                'name'             => $targetUser->name,
                'email'            => $targetUser->email,
                'permission_level' => $level->value,
                'permission_label' => $level->label(),
                'abilities'        => $level->abilities(),
            ],
        ]);
    }

    /**
     * 取消对指定用户的相册授权
     * DELETE /user/albums/{id}/authorize/{user_id}
     */
    public function revoke(Request $request): Response
    {
        /** @var User $owner */
        $owner = Auth::user();
        /** @var Album|null $album */
        $album = $owner->albums()->find($request->route('id'));
        if (is_null($album)) {
            return $this->fail('不存在的相册或无权操作');
        }

        $targetUserId = (int) $request->route('user_id');
        if ($targetUserId <= 0) {
            return $this->fail('无效的用户ID');
        }

        $album->authorizedUsers()->detach($targetUserId);
        return $this->success('已取消授权');
    }

    /**
     * 获取当前用户被授权访问的相册列表（含权限级别）
     * GET /user/authorized-albums
     */
    public function myAuthorizedAlbums(Request $request): Response
    {
        /** @var User $user */
        $user = Auth::user();

        $albums = $user->authorizedAlbums()
            ->with('user:id,name,email')
            ->latest('album_user_authorizations.created_at')
            ->paginate(40);

        $albums->getCollection()->each(function (Album $album) {
            $level = AlbumAuthorizationLevel::fromIntSafe((int) $album->pivot->permission_level);
            $album->setAttribute('permission_level', $level->value);
            $album->setAttribute('permission_label', $level->label());
            $album->setAttribute('abilities', $level->abilities());
            $album->setVisible(['id', 'name', 'intro', 'image_num', 'user', 'permission_level', 'permission_label', 'abilities']);
            $album->user?->setVisible(['id', 'name', 'email']);
        });

        return $this->success('success', compact('albums'));
    }

    /**
     * 获取被授权相册中的图片列表（被授权用户调用，同时返回权限能力）
     * GET /user/authorized-albums/{id}/images
     */
    public function authorizedAlbumImages(Request $request): Response
    {
        /** @var User $user */
        $user = Auth::user();
        $albumId = (int) $request->route('id');

        // 验证该用户对此相册确实有授权
        $album = $user->authorizedAlbums()->find($albumId);
        if (is_null($album)) {
            return $this->fail('无权访问该相册或相册不存在');
        }

        $level = AlbumAuthorizationLevel::fromIntSafe((int) $album->pivot->permission_level);

        $images = $album->images()
            ->with('group', 'strategy')
            ->latest()
            ->paginate(40);

        $images->getCollection()->each(function (Image $image) {
            $image->width      = max($image->width, 200);
            $image->height     = max($image->height, 200);
            $image->human_date = $image->created_at->diffForHumans();
            $image->date       = $image->created_at->format('Y-m-d H:i:s');
            $image->append(['url', 'thumb_url', 'filename', 'links'])
                ->setVisible(['id', 'filename', 'url', 'thumb_url', 'human_date', 'date', 'size', 'width', 'height', 'links']);
        });

        return $this->success('success', [
            'images'           => $images,
            'permission_level' => $level->value,
            'permission_label' => $level->label(),
            'abilities'        => $level->abilities(),
        ]);
    }

    /**
     * 究极权限：删除被授权相册中的图片
     * DELETE /user/authorized-albums/{id}/images
     * Body: [imageId1, imageId2, ...]
     */
    public function deleteAuthorizedAlbumImages(Request $request): Response
    {
        /** @var User $user */
        $user = Auth::user();
        $albumId = (int) $request->route('id');

        // 验证授权关系
        $album = $user->authorizedAlbums()->find($albumId);
        if (is_null($album)) {
            return $this->fail('无权访问该相册或相册不存在');
        }

        // 验证权限级别必须为究极
        $level = AlbumAuthorizationLevel::fromIntSafe((int) $album->pivot->permission_level);
        if (! $level->can('delete')) {
            return $this->fail('您的权限级别（' . $level->label() . '）不支持删除操作，请联系相册所有者升级权限');
        }

        $imageIds = (array) $request->all();
        if (empty($imageIds)) {
            return $this->fail('请选择要删除的图片');
        }

        // 只允许删除该相册内的图片（通过 album_id 过滤，避免越权）
        $albumImageIds = $album->images()->whereIn('id', $imageIds)->pluck('id')->toArray();
        if (empty($albumImageIds)) {
            return $this->fail('未找到可删除的图片');
        }

        // 以相册所有者身份执行删除（物理删除需要所有者账号上下文）
        $albumOwner = $album->user;
        (new UserService())->deleteImages($albumImageIds, $albumOwner);

        return $this->success('删除成功');
    }
}
