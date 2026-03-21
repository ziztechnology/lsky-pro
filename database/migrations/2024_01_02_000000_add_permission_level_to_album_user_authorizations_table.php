<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     * 为相册授权表新增权限级别字段
     * 1 = readonly  只读（仅浏览）
     * 2 = advanced  高级（浏览 + 下载）
     * 3 = ultimate  究极（浏览 + 下载 + 删除）
     *
     * @return void
     */
    public function up()
    {
        Schema::table('album_user_authorizations', function (Blueprint $table) {
            $table->unsignedTinyInteger('permission_level')
                ->default(1)
                ->comment('授权级别: 1=只读, 2=高级(下载), 3=究极(删除)')
                ->after('user_id');
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        Schema::table('album_user_authorizations', function (Blueprint $table) {
            $table->dropColumn('permission_level');
        });
    }
};
