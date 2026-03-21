<?php

namespace App\Http\Controllers\User;

use App\Http\Controllers\Controller;
use App\Models\Album;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Auth;

class AlbumAuthorizationController extends Controller
{
    /**
     * 获取指定相册已授权的用户列表（仅相册所有者可查看）
     */
    public function authorizedUsers(Request $request): Response
    {
        /** @var User $user */
        $user = Auth::user();

        /** @var Album|null $album */
        $album = $user->albums()->find($request->route('id'));
        if (is_null($album)) {
            return $this->fail('不存在的相册或无权操作');
        }

        $authorizedUsers = $album->authorizedUsers()
            ->select('users.id', 'users.name', 'users.email')
            ->get();

        return $this->success('success', compact('authorizedUsers'));
    }

    /**
     * 授权指定用户访问相册（通过邮箱查找用户）
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

        // 检查是否已授权
        if ($album->authorizedUsers()->where('users.id', $targetUser->id)->exists()) {
            return $this->fail('该用户已拥有访问权限');
        }

        $album->authorizedUsers()->attach($targetUser->id);

        return $this->success('授权成功', [
            'user' => [
                'id'    => $targetUser->id,
                'name'  => $targetUser->name,
                'email' => $targetUser->email,
            ]
        ]);
    }

    /**
     * 取消对指定用户的相册授权
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
     * 获取当前用户被授权访问的相册列表
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
            $album->setVisible(['id', 'name', 'intro', 'image_num', 'user']);
            $album->user?->setVisible(['id', 'name', 'email']);
        });

        return $this->success('success', compact('albums'));
    }

    /**
     * 获取被授权相册中的图片列表（被授权用户调用）
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

        $images = $album->images()
            ->with('group', 'strategy')
            ->latest()
            ->paginate(40);

        $images->getCollection()->each(function ($image) {
            $image->width     = max($image->width, 200);
            $image->height    = max($image->height, 200);
            $image->human_date = $image->created_at->diffForHumans();
            $image->date      = $image->created_at->format('Y-m-d H:i:s');
            $image->append(['url', 'thumb_url', 'filename', 'links'])
                ->setVisible(['id', 'filename', 'url', 'thumb_url', 'human_date', 'date', 'size', 'width', 'height', 'links']);
        });

        return $this->success('success', compact('images'));
    }
}
